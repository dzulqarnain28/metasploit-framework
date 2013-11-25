# Synchronizes {#metasploit_instance metasploit instance's}
# {Msf::Module#targets} to
# {#module_instance} `Metasploit::Model::Module::Instance#targets`.
class Metasploit::Framework::Module::Instance::Synchronization::Targets < Metasploit::Framework::Module::Instance::Synchronization::Base
  extend Metasploit::Framework::Synchronizes

  #
  # CONSTANTS
  #

  ALLOW_BY_ATTRIBUTE = {
      targets: true
  }

  #
  # Synchronization
  #

  synchronize do
    destroy_removed
    synchronize_module_target_associations
    synchronize_module_instance_associations
  end

  synchronizes :target_architectures,
               :target_platforms,
               for: 'Module::Target'
  synchronizes :module_architectures,
               :module_platforms,
               for: 'Module::Instance'

  #
  # Methods
  #

  def destination_attributes_set
    unless instance_variable_defined? :@destination_attributes_set
      if destination.new_record?
        @destination_attributes_set = Set.new
      else
        @destination_attributes_set = Set.new destination_targets.map(&:name)
      end
    end

    @destination_attributes_set
  end

  def destination_targets
    @destination_targets = scope.to_a
  end

  def destroy_removed
    unless destination.new_record? || removed_attributes_set.empty?
      scope.where(
          # AREL cannot visit Set
          name: removed_attributes_set.to_a
      ).destroy_all
    end
  end

  def module_target_by_name
    unless instance_variable_defined? :@module_target_by_name
      module_target_by_name = Hash.new { |hash, name|
        hash[name] = destination.targets.build(
            name: name
        )
      }

      @module_target_by_name = unchanged_module_targets.each_with_object(module_target_by_name) { |module_target, module_target_by_name|
        module_target_by_name[module_target.name] = module_target
      }
    end

    @module_target_by_name
  end

  def scope
    destination.targets.includes(
        target_architectures: :architecture,
        target_platforms: :platform
    )
  end

  def synchronize_module_instance_associations
    self.class.synchronization_classes(for: 'Module::Instance') do |synchronization_class|
      synchronization = synchronization_class.new(
          destination: destination,
          source: source
      )
      synchronization.valid!

      synchronization.synchronize
    end
  end

  def synchronize_module_target_associations
    source_targets.each do |msf_module_target|
      name  = msf_module_target.name
      module_target = module_target_by_name[name]

      self.class.synchronization_classes(for: 'Module::Target') do |synchronization_class|
        synchronization = synchronization_class.new(
          destination: module_target,
          source: msf_module_target
        )
        synchronization.valid!

        synchronization.synchronize
      end
    end
  end

  def source_attributes_set
    @source_attributes_set ||= Set.new source_targets.map(&:name)
  end

  def source_targets
    begin
      source.targets
    rescue NoMethodError => error
      log_module_instance_error(destination, error)

      []
    end
  end

  def unchanged_attributes_set
    @unchanged_attributes_set ||= destination_attributes_set & source_attributes_set
  end

  def unchanged_module_targets
    unless instance_variable_defined? :@unchanged_module_targets
      if destination.new_record? || unchanged_attributes_set.empty?
        @unchanged_module_targets = []
      else
        @unchanged_module_targets = destination_targets.select { |module_target|
          unchanged_attributes_set.include? module_target.name
        }
      end
    end

    @unchanged_module_targets
  end
end