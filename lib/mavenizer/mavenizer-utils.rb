require 'fileutils'
require 'logger'

module Mavenizer

  #----------------------------------------
  # Log
  #----------------------------------------
  module Log
    @@log = Logger.new(STDOUT)
  end
  
  #----------------------------------------
  # Utils
  #----------------------------------------
  class Utils
    
    include Log 

    def self.copy_files root_dir, context_dir, sources, target, excludes
      FileUtils.mkdir_p(target) unless File.exist?(target)

      sources.each do |source_item|
        if context_dir
          source_full = File.join(root_dir, context_dir, source_item)
        else
          source_full = File.join(root_dir, source_item)
        end
        source_dir_full = (File.directory?(source_full) ? source_full : File.dirname(source_full))    
        Dir.chdir(source_dir_full)
        all_items = Dir.glob(File.join("**", "*.*"), File::FNM_DOTMATCH).find_all{|item| /\/?\.+$/ !~ item && !File.directory?(item)}
        files = all_items.find_all do |item|
          if File.directory? source_full
            yield item
          else
            item == source_item
          end
        end
        @@log.info "Copying #{files.size} files from #{source_dir_full}"
        excludedCount=0
        files.each do |file|
          
          exclude=false
          excludes.each{ |it|
            if !exclude 
              relativePath = File.join(source_item, file)
              exclude=it.match(File.join(source_item, file))!=nil
            end
          }
          if !exclude
            target_file = File.join(target,source_item, file)
            FileUtils.mkdir_p(File.dirname(target_file)) unless File.exist?(File.dirname(target_file))
            FileUtils.copy_file file, target_file
          else
            excludedCount+=1
          end
        end
        @@log.info "Files copied #{files.size-excludedCount} excluded #{excludedCount}"
      end
    end
    
  end

end