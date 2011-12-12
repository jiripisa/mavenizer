$:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'erb'
require 'singleton'
require 'fileutils'
require 'rexml/document'
require 'pathname'
require 'mavenizer/mavenizer-model'
require 'mavenizer/mavenizer-utils'
require 'mavenizer/mavenizer-pretty'

module Mavenizer

  #----------------------------------------
  # Migration context
  #----------------------------------------
  class MigrationContext
    include Singleton

    attr_reader :projects  

    def initialize
      @projects = {}
    end

    def add_project project
      @projects[project.project_id] = project
    end
  end

  #----------------------------------------
  # Project convertor
  #----------------------------------------
  class ProjectConvertor

    include Singleton
    include Log

    attr_accessor :settings
    attr_accessor :root_dir
    attr_accessor :from_scratch_mode

    def initialize
      @erb = ERB.new(File.new(File.join(File.dirname(__FILE__), 'mavenizer/pom.erb')).read)
    end

    def prepare_install dependencies
      _3rd_party_libs = '3rd_party_libs'
      third_party_lib_dir = File.join(target_dir, _3rd_party_libs)
      FileUtils.mkdir_p third_party_lib_dir
      @@log.info("-------------------------------------------------")
      @@log.info("| Preparing libraries for deployment")
      @@log.info("-------------------------------------------------")
      File.open( File.join(target_dir, 'deploy.sh'), "w") do |shout|
      File.open( File.join(target_dir, 'deploy.bat'), "w") do |out|
        out.puts "set REPOSITORY_URL=#{@settings[:repository_url]}"
        out.puts "set REPOSITORY_ID=#{@settings[:repository_id]}"
        shout.puts "REPOSITORY_URL=#{@settings[:repository_url]}"
        shout.puts "REPOSITORY_ID=#{@settings[:repository_id]}"
        dependencies.each do |dependency|
          jar_file = File.basename(dependency.path)
          jar_dir = File.join(dependency.groupId.split('.'), dependency.version)
          @@log.info("Copying #{jar_file}")
          jar_file_path = File.join(third_party_lib_dir, jar_dir, jar_file)
          d_file = File.join(_3rd_party_libs, jar_dir, jar_file)
          FileUtils.mkdir_p File.dirname(jar_file_path)
          if (File.exists? dependency.path)
            file_to_copy = dependency.path
          else
            file_to_copy = File.join(@root_dir, 'jars', File.basename(dependency.path))
          end
          FileUtils.copy_file file_to_copy, jar_file_path
          out.puts "call mvn deploy:deploy-file -DrepositoryId=%REPOSITORY_ID% -Durl=%REPOSITORY_URL% -Dfile=#{d_file} -DartifactId=#{dependency.artifactId} -DgroupId=#{dependency.groupId} -Dversion=#{dependency.version} -Dpackaging=jar -DgeneratePom=true"
          shout.puts "mvn deploy:deploy-file -DrepositoryId=$REPOSITORY_ID -Durl=$REPOSITORY_URL -Dfile=#{d_file} -DartifactId=#{dependency.artifactId} -DgroupId=#{dependency.groupId} -Dversion=#{dependency.version} -Dpackaging=jar -DgeneratePom=true"
        end
       end
      end
    end

    #Used for the 'from-scratch' mode
    def convert project
      @@log.info("-------------------------------------------------")
      @@log.info("| Converting #{project.project_id}")
      @@log.info("-------------------------------------------------")
      unless ARGV.include? 'skipCopy'
        prepare_dir project
        copy_src project
        copy_omi project
        copy_resources project
        copy_webapp project
      end
      save_pom project
    end

    def clean_target_dir
      @@log.info "Removing #{target_dir}"
      FileUtils.rm_rf(target_dir)
    end

    #Used only for the add-pom mode.
    def create_pom project
      prjct_dir = project.directory ? File.join(source_dir, project.directory) : source_dir
      pom_file = File.join(prjct_dir, "pom.xml")
      save_pom_to_file(pom_file, project)
    end

    private

    def relative_path(parent_project, module_project)
      if from_scratch_mode
        return module_project.name  
      else
        parent_project_dir = parent_project.directory ? File.join(source_dir, parent_project.directory) : source_dir
        module_project_dir = module_project.directory ? File.join(source_dir, module_project.directory) : source_dir
        a = Pathname.new(parent_project_dir)
        b = Pathname.new(module_project_dir)
        return b.relative_path_from(a)
      end
    end

    def save_pom_to_file(pom_file, project)
      @@log.info "Saving #{pom_file}"
      pom = @erb.result(binding)
      xml = REXML::Document.new(pom)
      formatter = REXML::Formatters::JirkowoPretty.new(4)
      formatter.compact = true
      formatter.width = 5000
      formatter.width
      File.open( pom_file, "w+") {|out| formatter.write(xml, out)}
    end

    def save_pom project
      pom_file = File.join(directory(project), "pom.xml")
      save_pom_to_file(pom_file, project)
    end

    def prepare_dir project
      @@log.info "Preparing directory for #{project.project_id}"
      FileUtils.mkdir_p(directory project)
    end

    def copy_src project
      unless project.java_sources.empty?
        #Full path to the target/src/main/java
        target = File.join(directory(project), "src", "main", "java");
        Utils.copy_files(source_dir, project.directory, project.java_sources, target, project.java_sources_exclude){|file| file.split('.').last == 'java'}
      end
    end

    def copy_omi project
      directories = project.resource_dirs + project.java_sources + project.resource_files
      unless directories.empty?
        #Full path to the target/src/main/java
        target = File.join(directory(project), "src", "main", project.packaging != 'ear' ? "meta/system/omi" : "application");
        Utils.copy_files(source_dir, project.directory, directories, target, project.resource_files_exclude){|file| file.split('.').last == 'omi'}    
      end
    end

    def copy_resources project
      directories = project.resource_dirs + project.java_sources + project.resource_files
      unless directories.empty?
        #Full path to the target/src/main/java
        target = File.join(directory(project), "src", "main", project.packaging != 'ear' ? "resources" : "application");
        Utils.copy_files(source_dir, project.directory, directories, target, project.resource_files_exclude){|file| file.split('.').last != 'java' && file.split('.').last != 'jar' && file.split('.').last != 'omi' && file.scan('CVS').empty?}    
      end
    end

    def copy_webapp project
      unless project.webapp_sources.empty?
        target = File.join(directory(project), "src", "main", "webapp");
        Utils.copy_files(source_dir, project.directory, project.webapp_sources, target){|file| file.scan('CVS').empty? && file !~ /\S+\/lib\/\S+\.jar/}
      end
    end

    def directory project
      if project.parent
        directory = File.join(directory(find_project(project.parent)), project.name)
      else
        directory = File.join(target_dir, project.name)
      end
      return directory
    end
  
    def find_project project_id
      if MigrationContext.instance.projects.key? project_id
        MigrationContext.instance.projects[project_id]
      else
        raise "Project #{project_id} not found"
      end
    end

    def target_dir
      self.settings[:target]
    end

    def source_dir
      self.settings[:source]
    end

    def plugin p
      plugin_id = p[0]
      context = p.size > 1 ? p[1][0] : {}
      erb_base_file = "mvn_plugins/#{plugin_id}.erb"
      if File.exist? File.join(self.root_dir, erb_base_file)
        erb_file = File.new(File.join(self.root_dir, erb_base_file))
      else
        erb_file = File.new(File.join(File.dirname(__FILE__), "mavenizer/#{erb_base_file}"))
      end
      plugin_erb = ERB.new(erb_file.read)
      plugin_erb.result(binding)
    end

  end

  #----------------------------------------
  # Execution context
  #----------------------------------------
  class ExecutionContext

    def execute &block
      instance_eval &block
    end

    def method_missing(symbol, *args)
      require symbol.to_s
    end

  end

  #----------------------------------------
  # DSL magic :)
  #----------------------------------------
  def method_missing(symbol, *args, &block)
    puts symbol if ARGV.include? 'trace'

    project = Project.new symbol
    project.setup &block

    #Storage of all loaded projects
    MigrationContext.instance.add_project(project)
  end

  def convert settings, &block
    ProjectConvertor.instance.settings = settings;
    ProjectConvertor.instance.from_scratch_mode = (settings[:source] != settings[:target])
    ProjectConvertor.instance.root_dir = Dir.pwd;

    Project.default_group_id= settings[:groupId] if settings[:groupId]
    Project.default_version= settings[:version] if settings[:version]
    Project.name_format= settings[:name_format] if settings[:name_format]
    Project.install_artifact= ARGV.include?'install'

    ProjectConvertor.instance.clean_target_dir if (ARGV.include? 'clean')

    ExecutionContext.new.execute &block



    if (ProjectConvertor.instance.from_scratch_mode)
      MigrationContext.instance.projects.each_value{|project| ProjectConvertor.instance.convert project}
      if ARGV.include? 'generate-install'
        dependencies_4_install = []
        MigrationContext.instance.projects.each_value{|project| (project.dependencyManagementItems + project.dependencies).each {|d| dependencies_4_install << d if d.path}}
        ProjectConvertor.instance.prepare_install dependencies_4_install
      end
    else
      MigrationContext.instance.projects.each_value{|project| ProjectConvertor.instance.create_pom project}
    end
  end

end

include Mavenizer