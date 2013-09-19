class Metasploit::Framework::Module::Cache < Metasploit::Model::Base
  #
  # Attributes
  #

  # @!attribute [rw] module_manager
  #   The module manager using this cache.
  #
  #   @return [Msf::ModuleManager]
  attr_accessor :module_manager

  #
  # Validations
  #

  validates :module_manager,
            :presence => true

  #
  # Methods
  #

  delegate :module_type_enabled?, to: :module_manager

  # Set of paths this cache using to load `Metasploit::Model::Ancestors`.
  #
  # @return [Metasploit::Framework::Module::PathSet::Base]
  def path_set
    unless instance_variable_defined? :@path_set
      path_set = Metasploit::Framework::Module::PathSet::Database.new(
          cache: self
      )
      path_set.valid!

      @path_set = path_set
    end

    @path_set
  end

  # Checks that this cache is up-to-date by scanning the
  # `Metasploit::Model::Path#real_path` of each `Metasploit::Module::Path` in
  # {#path_set} for updates to `Metasploit::Model::Module::Ancestors`.
  #
  # @param options [Hash]
  # @option options [nil, Metasploit::Model::Module::Path, Array<Metasploit::Model::Module::Path>] :only only prefetch
  #   the given module paths.  If :only is not given, then all module paths in
  #   {#path_set} will be prefetched.
  # @return [void]
  # @raise (see Metasploit::Framework::Module::PathSet::Base#superset!)
  def prefetch(options={})
    options.assert_valid_keys(:only)

    module_paths = Array.wrap(options[:only])

    if module_paths.blank?
      module_paths = path_set.all
    else
      path_set.superset!(module_paths)
    end

    # TODO generalize to work with or without ActiveRecord for in-memory models
    ActiveRecord::Base.connection_pool.with_connection do
      module_paths.each do |module_path|
        module_path_load = Metasploit::Framework::Module::Path::Load.new(
            cache: self,
            module_path: module_path
        )

        module_path_load.each_module_ancestor_load do |module_ancestor_load|
          # TODO log validation errors
          if module_ancestor_load.valid?
            module_set = module_manager.module_set_by_module_type[module_ancestor_load.module_ancestor.module_type]
            module_set.derive_module_class(module_ancestor_load)
          end
        end
      end
    end
  end
end