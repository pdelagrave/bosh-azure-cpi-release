require 'spec_helper'
require "unit/cloud/shared_stuff.rb"

describe Bosh::AzureCloud::Cloud do
  include_context "shared stuff"

  describe '#create_vm' do
    # Parameters
    let(:agent_id) { "e55144a3-0c06-4240-8f15-9a7bc7b35d1f" }
    let(:stemcell_id) { "bosh-stemcell-xxx" }
    let(:light_stemcell_id) { "bosh-light-stemcell-xxx" }
    let(:resource_pool) { {'instance_type' => 'fake-vm-size'} }
    let(:networks_spec) { {} }
    let(:disk_locality) { double("disk locality") }
    let(:environment) { double("environment") }
    let(:resource_group_name) { MOCK_RESOURCE_GROUP_NAME }
    let(:virtual_network_name) { "fake-virual-network-name" }
    let(:location) { "fake-location" }
    let(:vnet) { {:location => location} }
    let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) } 
    let(:network) { instance_double(Bosh::AzureCloud::ManualNetwork) }
    let(:network_configurator) { double("network configurator") }
    let(:stemcell_info) { instance_double(Bosh::AzureCloud::Helpers::StemcellInfo) }

    before do
      allow(network_configurator).to receive(:networks).
        and_return([network])
      allow(network).to receive(:resource_group_name).
        and_return(resource_group_name)
      allow(network).to receive(:virtual_network_name).
        and_return(virtual_network_name)
      allow(client2).to receive(:get_virtual_network_by_name).
        with(resource_group_name, virtual_network_name).
        and_return(vnet)
    end

    context 'when vnet is not found' do
      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties, networks_spec).
          and_return(network_configurator)
        allow(client2).to receive(:get_virtual_network_by_name).
          with(resource_group_name, virtual_network_name).
          and_return(nil)
      end

      it 'should raise an error' do
        expect {
          cloud.create_vm(
            agent_id,
            stemcell_id,
            resource_pool,
            networks_spec,
            disk_locality,
            environment
          )
        }.to raise_error(/Cannot find the virtual network/)
      end
    end

    context 'when use_managed_disks is not set' do
      # The return value of create_vm
      let(:instance_id) { "#{MOCK_DEFAULT_STORAGE_ACCOUNT_NAME}-#{agent_id}" }
      let(:vm_params) {
        {
          :name => instance_id
        }
      }

      let(:storage_account_name) { MOCK_DEFAULT_STORAGE_ACCOUNT_NAME }
      let(:storage_account) {
        {
          :id => "foo",
          :name => storage_account_name,
          :location => location,
          :provisioning_state => "bar",
          :account_type => "foo",
          :storage_blob_host => "fake-blob-endpoint",
          :storage_table_host => "fake-table-endpoint"
        }
      }

      before do
        allow(storage_account_manager).to receive(:get_storage_account_from_resource_pool).
          with(resource_pool, location).
          and_return(storage_account)
        allow(stemcell_manager).to receive(:has_stemcell?).
          with(storage_account_name, stemcell_id).
          and_return(true)
        allow(stemcell_manager).to receive(:get_stemcell_info).
          with(storage_account_name, stemcell_id).
          and_return(stemcell_info)
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties, networks_spec).
          and_return(network_configurator)
      end

      context 'when everything is OK' do
        context 'and a heavy stemcell is used' do
          it 'should create the VM' do
            expect(vm_manager).to receive(:create).
              with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
              and_return(vm_params)
            expect(registry).to receive(:update_settings)

            expect(stemcell_manager).to receive(:get_stemcell_info)
            expect(light_stemcell_manager).not_to receive(:has_stemcell?)
            expect(light_stemcell_manager).not_to receive(:get_stemcell_info)

            expect(
              cloud.create_vm(
                agent_id,
                stemcell_id,
                resource_pool,
                networks_spec,
                disk_locality,
                environment
              )
            ).to eq(instance_id)
          end
        end

        context 'and a light stemcell is used' do
          before do
            allow(light_stemcell_manager).to receive(:has_stemcell?).
              with(location, light_stemcell_id).
              and_return(true)
            allow(light_stemcell_manager).to receive(:get_stemcell_info).
              with(light_stemcell_id).
              and_return(stemcell_info)
          end

          it 'should create the VM' do
            expect(vm_manager).to receive(:create).
              with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
              and_return(vm_params)
            expect(registry).to receive(:update_settings)

            expect(light_stemcell_manager).to receive(:has_stemcell?)
            expect(light_stemcell_manager).to receive(:get_stemcell_info)
            expect(stemcell_manager).not_to receive(:get_stemcell_info)

            expect(
              cloud.create_vm(
                agent_id,
                light_stemcell_id,
                resource_pool,
                networks_spec,
                disk_locality,
                environment
              )
            ).to eq(instance_id)
          end
        end
      end

      context 'when it failed to get the user image info' do
        before do
          allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
            with(azure_properties_managed, networks_spec).
            and_return(network_configurator)
          allow(stemcell_manager2).to receive(:get_user_image_info).and_raise(StandardError)
        end

        it 'should raise an error' do
          expect {
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error(/Failed to get the user image information for the stemcell `#{stemcell_id}'/)
        end
      end

      context 'when stemcell_id is invalid' do
        before do
          allow(stemcell_manager).to receive(:has_stemcell?).
            with(storage_account_name, stemcell_id).
            and_return(false)
        end

        it 'should raise an error' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error("Given stemcell `#{stemcell_id}' does not exist")
        end
      end

      context 'when network configurator fails' do
        before do
          allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
            and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error StandardError
        end
      end

      context 'when new vm is not created' do
        before do
          allow(vm_manager).to receive(:create).and_raise(StandardError)
        end

        it 'failed to creat new vm' do
          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error StandardError
        end
      end

      context 'when registry fails to update' do
        before do
          allow(vm_manager).to receive(:create)
          allow(registry).to receive(:update_settings).and_raise(StandardError)
        end

        it 'deletes the vm' do
          expect(vm_manager).to receive(:delete).with(instance_id)

          expect {
            cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          }.to raise_error(StandardError)
        end
      end
    end

    context 'when use_managed_disks is set' do
      # The return value of create_vm
      let(:instance_id) { agent_id }
      let(:vm_params) {
        {
          :name => instance_id
        }
      }

      before do
        allow(Bosh::AzureCloud::NetworkConfigurator).to receive(:new).
          with(azure_properties_managed, networks_spec).
          and_return(network_configurator)
      end

      context 'when a heavy stemcell is used' do
        before do
          allow(stemcell_manager2).to receive(:get_user_image_info).
            and_return(stemcell_info)
        end

        it 'should create the VM' do
          expect(vm_manager).to receive(:create).
            with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
            and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(
            managed_cloud.create_vm(
              agent_id,
              stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id)
        end
      end

      context 'when a light stemcell is used' do
        before do
          allow(light_stemcell_manager).to receive(:has_stemcell?).
            with(location, light_stemcell_id).
            and_return(true)
          allow(light_stemcell_manager).to receive(:get_stemcell_info).
            with(light_stemcell_id).
            and_return(stemcell_info)
        end

        it 'should create the VM' do
          expect(vm_manager).to receive(:create).
            with(instance_id, location, stemcell_info, resource_pool, network_configurator, environment).
            and_return(vm_params)
          expect(registry).to receive(:update_settings)

          expect(light_stemcell_manager).to receive(:has_stemcell?)
          expect(light_stemcell_manager).to receive(:get_stemcell_info)

          expect(
            managed_cloud.create_vm(
              agent_id,
              light_stemcell_id,
              resource_pool,
              networks_spec,
              disk_locality,
              environment
            )
          ).to eq(instance_id)
        end
      end
    end
  end
end
