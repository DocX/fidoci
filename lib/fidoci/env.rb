module Fidoci
    # Environment configuration of D
    # encapsulates container image building and running commands in it
    class Env
        attr_accessor :env_config

        def initialize(image, name, env_config)
            @name = name.to_s
            @image = image
            @env_config = env_config
        end

        def build_image()
            if image_exists?
                puts "Using exisitng image #{image_name}..."
                return true
            end

            puts "Building image #{image_name}..."
            params = []

            params << '--force-rm=true'
            params << "-t #{image_name}"
            if env_config['dockerfile']
                params << "-f #{env_config['dockerfile']}"
            end

            system "docker build #{params.join(' ')} ."
        end

        def image_name
            "%s:%s" % [@image, @name]
        end

        def image_exists?
            images = `docker images`
            images_names  = images.split("\n").drop(1).map{|line|
                parts = line.split(/\s+/)
                parts[0..1].join(':')
            }

            images_names.any?{|i| i == image_name}
        end

        def cmd(*args)
            if build_image
                puts "Running `#{args.join(' ')}`..."
                system "docker-compose run --rm #{@name} #{args.join(' ')}"
            else
                puts "Build failed"
                return false
            end
        end

        def commands
            return false unless env_config['commands']

            success = env_config['commands'].all? { |command|
                cmd command.split(/\s+/)
            }

            puts "Test failed" unless success
            success
        end
    end
end