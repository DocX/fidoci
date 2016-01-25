require 'io/console'

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

        def debug(msg)
            puts msg if ENV['DEBUG']
        end

        def info(msg)
            puts msg
        end

        def build_image
            image = Docker::Image.get(image_name) rescue nil
            unless image
                image = do_build_image
            end

            image
        end

        def do_build_image
            info "Building image #{image_name}..."
            params = {}

            params['forcerm'] = true
            params['t'] = image_name
            if env_config['dockerfile']
                params['dockerfile'] = env_config['dockerfile']
            end

            last_intermediate_image = nil
            image = Docker::Image.build_from_dir('.', params) do |chunk|
                json = JSON.parse(chunk)
                if (json['stream'] =~ /\ --->\ ([a-f0-9]{12})/) == 0
                    last_intermediate_image = $1
                end
                $stdout << json['stream']
            end
            last_intermediate_image = nil

            image
        ensure
            begin
                if last_intermediate_image
                    img = Docker::Image.get(last_intermediate_image)
                    img.json
                    puts "Removing intermediate image #{last_intermediate_image}"
                    img.remove('force' => true)
                end
            rescue
                nil
            end
        end

        def image_name
            "%s:%s" % [@image, @name]
        end

        def tag_image(tag)
            info "Tagging images as #{@image}:#{tag}..."

            image = Docker::Image.get(image_name)
            image.tag('repo' => @image, 'tag' => tag, 'force' => true)
        end

        def push(tag)
            repo_tag = "#{@image}:#{tag}"
            image = Docker::Image.get(repo_tag)

            if ENV['DOCKER_AUTH_FILE']
              # load file
              auth_file = JSON.parse(File.read ENV['DOCKER_AUTH_FILE'])
              image_parts = @image.split('/')
	      registry = image_parts.size == 2 ? "https://#{image_parts[0]}" : "https://index.docker.io/v1/"
              creds = auth_file['auths'][registry]
              if creds['auth']
                creds['username'], creds['password'] = Base64.decode64(creds['auth']).split(':', 2)
                creds.delete 'auth'
              end
            else
              creds = {
                'username' => ENV['DOCKER_REGISTRY_USERNAME'],
                'password' => ENV['DOCKER_REGISTRY_PASSWORD'],
                'email' => ENV['DOCKER_REGISTRY_EMAIL']
              }
            end
   
            info "Pushing #{repo_tag}..."
            image.push(creds, 'repo_tag' => repo_tag) do |msg|
                json = JSON.parse(msg)
                $stdout.puts json['status']
                $stdout.puts json['progress'] if json['progress']
                $stdout.puts "Error: #{json['error']}" if json['error']
            end
        end

        def container_name
            @image.gsub(/[^a-zA-Z0-9_]/, '_') + "_" + @name.gsub(/[^a-zA-Z0-9_]/, '_')
        end

        def clean_image!
            begin
                debug "Cleaning image #{image_name}"
                image = Docker::Image.get(image_name)
                image.remove(force: true)
            rescue
                true
            end
        end

        def clean_container(cname)
            begin
                debug "Cleaning container #{cname}..."
                container = Docker::Container.get(cname)
                container.remove(force: true, v: true)
            rescue
                debug "Cleaning failed"
                nil
            end
        end

        def links
            env_config['links'] || []
        end

        def clean_containers!
            containers = [container_name]
            containers += links.map{|key, config| link_container_name(key) }

            containers.each{|cname|
                clean_container(cname)
            }
            true
        end

        # clean images and containers associated with this Env
        def clean!
            clean_containers! rescue nil
            clean_image! rescue nil
        end

        # stop services and clean main container
        def stop!
            links.map{|key, config|
                cname = link_container_name(key)
 		if links[key]['shared']
                    debug "Keeping running #{cname}..."
                    next
		end

                begin
                    debug "Stopping container #{cname}..."
                    container = Docker::Container.get(cname)
                    container.stop!
                rescue
                    nil
                end
            }
        end

        # run command in docker, building the image and starting services first
        # if needed
        def cmd(*args)
            if build_image && link_containers
                debug "Running `#{args.join(' ')}`..."
                docker_run_or_exec(*args)
            else
                debug "Build failed"
                return false
            end
        end

        def link_container_name(key)
            links[key]['shared'] || "#{container_name}_#{key}"
        end

        # starts link containers and return dict name:container_name
        def link_containers
            links.map {|key, link_config|
                [key, start_link(link_container_name(key), link_config)]
            }
        end

        def start_link(link_container_name, link_config)
            container = Docker::Container.get(link_container_name) rescue nil

            unless container
                params = {}
                params['name'] = link_container_name
                params['Image'] = link_config['image']

                config_params(params, link_config)

                debug "Creating container #{link_container_name}..."

                unless Docker::Image.exist?(link_config['image'])
                    # obtain image
                    link_image_name, link_image_tag = link_config['image'].split(':')
                    link_image_tag = 'latest' unless link_image_tag

                    full_image_name = "#{link_image_name}:#{link_image_tag}"
                    Docker::Image.create(fromImage: full_image_name)
                end

                container = Docker::Container.create(params)
            end

            unless container.json['State']['Running']
                debug "Starting container #{link_container_name}..."
                container.start!
            end

            debug "Using container #{link_container_name}..."

            link_container_name
        end

        def docker_run_or_exec(*args)
            container = Docker::Container.get(container_name) rescue nil

            if container
                docker_exec(container.id, *args)
            else
                docker_run(*args)
            end
        end

        def docker_exec(id, *args)
            params = {}
            params["Container"] = id
            params["AttachStdin"] = true
            params["AttachStdout"] = true
            params["AttachStderr"] = true
            params["Tty"] = true
            params["Cmd"] = args

            docker_exec = Docker::Exec.create(params)
            result = nil

            $stdin.raw do
                result = docker_exec.start!(tty: true, stdin: $stdin) do |msg|
                    $stdout << msg
                end
            end

            debug "Exited with status #{result[2]}"

            result[2]
        end

        # calls docker run command with all needed parameters
        # attaches stdin and stdout
        def docker_run(*args)
            params = {}
            params['AttachStdin'] = true
            params['OpenStdin'] = true
            params['Tty'] = true
            params['name'] = container_name

            # links
            link_containers.each{|name, container_name|
                params['HostConfig'] ||= {}
                params['HostConfig']['Links'] ||= []
                params['HostConfig']['Links'] << "#{container_name}:#{name}"
            }

            config_params(params, env_config)
            params['Image'] = image_name
            params['Cmd'] = args

            #puts params

            container = Docker::Container.create(params)

            receiver = ->(msg) {
                $stdout << msg
                $stdout.flush
            }

            if $stdin && $stdin.tty?

                $stdin.raw do
                    container.start!
                    lines, cols = IO.console.winsize rescue [60,80]
                    container.connection.post("/containers/#{container.id}/resize", h: lines, w: cols)
                    container.attach(tty: true, stdin: $stdin, &receiver)
                end
            else
                container.start!.attach(tty: true, &receiver)
            end

            status = container.json['State']['ExitCode']
            debug "Exited with status #{status}"

            status
        ensure
            clean_container(container_name)
        end

        def config_params(params, config)
            params['HostConfig'] ||= {}

            # env
            if config['environment']
                config['environment'].each {|key,val|
                    params['Env'] ||= []
                    params['Env'] << "#{key}=#{val}"
                }
            end

            if config['environment_pass']
                config['environment_pass'].each{|key|
                    params['Env'] ||= []
                    params['Env'] << "#{key}=#{ENV[key]}"

                    puts "Warning: Passing environment variable #{key} is not locally set" unless ENV[key]
                }
            end

            # volumes
            if config['volumes']
                config['volumes'].each {|v|
                    params['HostConfig']['Binds'] ||= []

                    host_path, container_path = v.split(':')
                    host_path = File.expand_path(host_path)

                    params['HostConfig']['Binds'] << "#{host_path}:#{container_path}"
                }
            end

            # ports
            if config['ports']
                config['ports'].each {|p|
                    parts = p.split(':')
                    container_port = parts.last
                    host_port = parts[-2]
                    host_ip = parts[-3] || ""

                    params['HostConfig']['PortBindings'] ||= {}
                    params['HostConfig']['PortBindings']["#{container_port}/tcp"] = [
                        {
                            "HostIp" => host_ip,
                            "HostPort" => host_port
                        }
                    ]
                }
            end

            params
        end

        def commands
            return false unless env_config['commands']

            success = env_config['commands'].all? { |command|
                info "Running `#{command}`..."

                unless command.is_a? Array
                    command = command.split(/\s+/)
                end

                state = cmd(*command)
                info "Exited with state #{state}"

                state == 0
            }

            success
        end
    end
end
