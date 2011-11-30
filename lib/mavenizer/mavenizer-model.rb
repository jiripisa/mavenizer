require "mavenizer/mavenizer-utils" 

module Mavenizer

  #----------------------------------------
  # Artifact
  #----------------------------------------
  module ArtifactAttributes

    attr_accessor :artifactId
    attr_accessor :groupId
    attr_accessor :version
    attr_accessor :packaging

    def to_s
      "#{groupId}:#{artifactId}:#{version}"
    end
    
  end

  #----------------------------------------
  # Dependency
  #----------------------------------------
  class Dependency
    include ArtifactAttributes

    attr_accessor :scope
    attr_reader   :exclusions
    attr_accessor :systemPath
    attr_accessor :type
    attr_accessor :path

    #def full_keysss
    #  return "#{self.groupId}:#{self.artifactId}:#{self.version}:#{self.scope}"
    #end

    def q_name
      return "#{self.groupId}:#{self.artifactId}"
    end

    def exclusions=(value)
      @exclusions = []
      value.each do |exclusion|
        if (exclusion.is_a? Symbol)
          dep = MigrationContext.instance.projects[exclusion]
          exclusion_array = [dep.groupId, dep.artifactId]
        else
          exclusion_array = exclusion.split(':')
        end
        @exclusions << {:groupId => exclusion_array[0], :artifactId => exclusion_array[1]}
      end
    end
  end

  #----------------------------------------
  # ProjectProxy
  #----------------------------------------
  class ProjectProxy

    include Log

    def initialize project
      @project = project
    end

    def setup &block
      @@log.info "Loading #{@project.project_id}"
      instance_eval &block
    end

    def profile(profile_name, &block)
      @@log.info "Creating profile #{profile_name}"
      profile_project = Project.new(profile_name)
      other_proxy = ProjectProxy.new(profile_project)
      other_proxy.setup &block
      @project.profiles << profile_project
    end

    def method_missing(symbol, *args)
      if @project.respond_to? "#{symbol}="
        code = "@project.#{symbol} = args[0]"
        eval code
      else
        args_list = []
        args.each_index{|index| args_list << "args[#{index}]"}
        eval "@project.#{symbol}(#{args_list.join(',')})"
        #eval "@project.#{symbol}(args[0])"
      end
    end

  end

  #----------------------------------------
  # Project
  #----------------------------------------
  class Project

    include ArtifactAttributes
    include Log

    attr_reader   :project_id
    attr_reader   :dependencies
    attr_reader   :dependencyManagementItems
    attr_reader   :modules
    attr_reader   :java_sources
    attr_reader   :java_sources_exclude
    attr_reader   :resource_dirs
    attr_reader   :webapp_sources
    attr_reader   :plugins
    attr_reader   :properties
    attr_accessor :parent
    attr_accessor :directory
    attr_accessor :profiles
    attr_reader   :build_java_sources
    attr_reader   :build_resources
    attr_reader   :resource_files
    attr_reader   :resource_files_exclude

    @@default_group_id = nil
    @@default_version = '1.0-SNAPSHOT'
    @@name_format = :short
    @@install_artifact = false

    def self.install_artifact= (value)
      @@install_artifact = value
    end

    def self.default_group_id= (value)
      @@default_group_id = value
    end

    def self.default_version= (value)
      @@default_version = value
    end

    def self.name_format= (name_format)
      @@name_format = name_format
    end

    def initialize(id)
      @project_id = id
      @version = @@default_version
      @dependencies = []
      @dependencyManagementItems = []
      @java_sources = []
      @java_sources_exclude = []
      @resource_dirs = []
      @groupId = @@default_group_id if @@default_group_id
      @modules = []
      @webapp_sources = []
      @plugins = []
      @properties = []
      @profiles = []
      @build_java_sources = []
      @build_resources = []
      @resource_files = []
      @resource_files_exclude = []
    end

    def setup &block
      proxy = ProjectProxy.new self
      proxy.setup &block
      #instance_eval &block
    end

    def dependency artifactId, *settings
      add_dependency artifactId, @dependencies, settings
    end

    def dependencyManagement artifactId, *settings
      add_dependency artifactId, @dependencyManagementItems, settings do |dependency|
        if dependency.systemPath && dependency.scope != :system
          @@log.info "Installing #{dependency.q_name} to the local repository"
          system "mvn install:install-file -DgroupId=#{dependency.groupId} -DartifactId=#{dependency.artifactId} -Dversion=#{dependency.version} -Dpackaging=jar -Dfile=#{dependency.systemPath}" if @@install_artifact == true
          dependency.systemPath = nil
        end
      end
    end

    def subproject moduleId
      self.packaging= 'pom'
      @modules << moduleId
    end
  
    def java_source src
      @java_sources << src
    end

    def java_source_exclude src
      @java_sources_exclude << src
    end

    def resources dir
      @resource_dirs << dir
    end

    def resource file
      @resource_files << file
    end

    def resource_exclude file
      @resource_files_exclude << file
    end

    def property property
      name = property.keys[0]
      value = property[name]
      @properties << {:name => name, :value => value}
    end

    def plugin plugin_id, *settings
      @@log.debug "Adding plugin #{plugin_id} to #{self.project_id}"
      @plugins << [plugin_id, settings]
    end

    def build_java_source bjs
      @@log.debug "Adding build java source #{bjs} to #{self.project_id}"
      @build_java_sources << bjs
    end

    def build_resource br, *settings
      @@log.debug "Adding build resource #{br} to #{self.project_id}"
      settings.each do |setting|
        setting.each_key do |key|
          value = setting[key]
          setter = "def br.#{key}=(value)\n @mavenizer_#{key} = value\n end"
          getter = "def br.#{key}\n return @mavenizer_#{key}\n end"
          apply_setter = "br.#{key}=value"
          eval setter
          eval apply_setter
          eval getter
        end
      end
      @build_resources << br
    end

    def include_from file
      eval File.open(file).read
    end

    def webapp_source src
      @webapp_sources << src
    end

    def name
      return "#{self.groupId}.#{self.artifactId}" if @@name_format == :long
      return self.artifactId
    end

    private
    def add_dependency(artifactId, target_array, settings)
      d = Dependency.new
      if artifactId.is_a? Symbol
        d_proj = MigrationContext.instance.projects[artifactId]
        d.groupId = d_proj.groupId
        d.artifactId = d_proj.artifactId
        d.version = d_proj.version
      else
        d.groupId= artifactId.split(':')[0]
        d.artifactId= artifactId.split(':')[1]
      end
      settings.each do |setting|
        if setting.is_a? Hash
          setting.each_key{|key| eval "d.#{key} = setting[:#{key}] if setting[:#{key}]"}
        end
      end
      yield d if block_given?
      target_array << d     
    end
    
  end

end
