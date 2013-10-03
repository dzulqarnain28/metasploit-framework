require 'spec_helper'

describe Metasploit::Framework::Module::Path::Load do
  subject(:module_path_load) do
    described_class.new
  end

  context 'factories' do
    context 'metasploit_framework_module_path_load' do
      include_context 'database cleaner'

      subject(:metasploit_framework_module_path_load) do
        with_established_connection do
          FactoryGirl.build(:metasploit_framework_module_path_load)
        end
      end

      it { should be_valid }
    end
  end

  context 'validations' do
    it { should validate_presence_of :cache }
    it { should ensure_inclusion_of(:changed).in_array([false, true]) }
    it { should validate_presence_of :module_path }
  end

  context '#changed' do
    subject(:changed) do
      module_path_load.changed
    end

    it 'should default to false' do
      changed.should be_false
    end

    it 'should be settable and gettable' do
      changed = double('Changed')
      module_path_load.changed = changed
      module_path_load.changed.should == changed
    end
  end

  context '#each_module_ancestor' do
    include_context 'database cleaner'

    subject(:each_module_ancestor_load) do
      with_established_connection do
        module_path_load.each_module_ancestor_load
      end
    end

    context 'with module path load valid' do
      let(:module_path) do
        module_path_load.module_path
      end

      let(:module_path_load) do
        with_established_connection do
          FactoryGirl.build(:metasploit_framework_module_path_load)
        end
      end

      it 'should have valid module path load' do
        module_path_load.should be_valid
      end

      it 'should pass #changed to Mdm::Module::Path#each_changed_module_ancestor as :change option' do
        module_path.should_receive(:each_changed_module_ancestor).with(
            hash_including(
                changed: module_path_load.changed
            )
        )

        each_module_ancestor_load.to_a
      end

      context 'with no changed module ancestors' do
        specify {
          expect { |block|
            with_established_connection do
              module_path_load.each_module_ancestor_load(&block)
            end
          }.not_to yield_control
        }
      end

      context 'with changed module ancestors' do
        let!(:module_ancestors) do
          with_established_connection do
            # Build instead of create so only the on-disk file is created and not saved to the database so the
            # Mdm::Module::Ancestors count as changed (since they are new)
            FactoryGirl.build_list(:mdm_module_ancestor, 2, parent_path: module_path)
          end
        end

        it 'should yield Metasploit::Framework::Module::Ancestor::Load' do
          with_established_connection do
            module_path_load.each_module_ancestor_load do |module_ancestor_load|
              module_ancestor_load.should be_a Metasploit::Framework::Module::Ancestor::Load
            end
          end
        end

        it 'should make a Metasploit::Framework::Module::Ancestor::Load for each changed module ancestor' do
          actual_real_paths = []

          with_established_connection do
            module_path_load.each_module_ancestor_load do |module_ancestor_load|
              actual_real_paths << module_ancestor_load.module_ancestor.real_path
            end
          end

          # have to compare by real_path as module_ancestors are not saved to the database, so can't compare
          # ActiveRecords since they compare by #id.
          expected_real_paths = module_ancestors.map(&:derived_real_path)
          expect(actual_real_paths).to match_array(expected_real_paths)
        end
      end
    end

    context 'without valid module path load' do
      it 'should have invalid module path load' do
        module_path_load.should be_invalid
      end

      specify {
        expect { |block|
          module_path_load.each_module_ancestor_load(&block)
        }.not_to yield_control
      }
    end
  end

  context '#module_type_enabled?' do
    subject(:module_type_enabled?) do
      module_path_load.module_type_enabled? module_type
    end

    let(:cache) do
      double('Metasploit::Framework::Module::Cache')
    end

    let(:module_type) do
      FactoryGirl.generate :metasploit_model_module_type
    end

    before(:each) do
      module_path_load.stub(cache: cache)
    end

    it 'should delegate to #cache' do
      cache.should_receive(:module_type_enabled?).with(module_type)

      module_type_enabled?
    end
  end
end