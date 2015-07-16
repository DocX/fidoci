# FIDOCI

Swiss army knife for Dockerized development and continuous integration

Key objectives:

- **One command development setup** - *develop in same environment as production and without need of setting up all the services in your local OS, all with just one command*
- **Seamlessly build and test container** - *build and test your application without setting up build environments. Jenkins builds become easy*
- **Keep no mess** - *fidoci is dilligent in cleaning up after itself. It is designed to be used on automated build servers.*

Dockerized conventions pushed by fidoci:

- **Production containers are testeable** - the same image is tested and shipped to the production
- **All dependencies are containers too** - there is probalby container for your 3rd party service, and if you need fidling, you can always fork your image.


## Get started

*Note: All the examples here are based around Ruby on Rails app. But fidoci is app/lang agnostic - the same as docker itself.*

Install ```fidoci``` gem (you need ruby installed on your system):

```shell
   gem install fidoci
```

Create your ```Dockerfile```, for example:

```dockerfile  
  FROM ruby:2.2
  ADD . /root/app
  WORKDIR /root/app
  RUN bundle install
  CMD bundle exec puma -e production
```

Setup your ```d.yml``` file in the root of your application:

```yaml
   image: despictable-me/container-full-of-minions
   
   dev:
     # if you want specific image for development (ie without bundle install)
     dockerfile: Dockerfile.development
     # some fixed development variables
     environment:
       NUMBER_OF_MINIONS: 10000
       DATABASE_HOSTNAME: minion_postgres # note links below
       DATABASE_PASSWORD: postgr3spwd
     # dev variables you don't want to store in Git
     environemnt_pass:
       - SECRET_TOKEN
     # mount local dir to container app dir
     volumes:
       - .:/root/app
     # bind containe port 3000 to local 0.0.0.0:3000
     ports:
       - "0.0.0.0:3000:3000"
     # describe dependent services (as containers of course)
     links:
       minion_postgres:
         image: postgres:9.4
         environment:
           POSTGRES_PASSWORD: postgr3spwd
```

Start developing...

```shell
  export SECRET_TOKEN="ilov<3banana"
  d bundle exec rails s
  # or 
  d /bin/bash
```

### What it does?

The ```d cmd args...``` command starts fidoci in development mode. It means this:

1. If not built, suilds your local ```image``` docker image with ```dev``` tag using ```dockerfile``` file (```Dockerfile``` if config is omited).
2. If not running, starts all ```links``` conainers named by the keys (```minion_postgress```) appended to underscorized image name with given configuration.
3. Runs command following ```d``` in container using built image in terminal interactive mode with
   - linked all ```links``` containers with aliases by their keys in ```d.yml``` file
   - environment variables defined in ```environment``` object and ```environment_pass``` list
   - mounted ```volumes```
   - bound ```ports```
4. After container exists stops all ```links``` containers (but keep them in dev mode, so you don't loose development database)

## Continuous integration 

To start using fidoci for continuous integration, add ```build``` section to ```d.yml``` file:

```yaml
   # ... dev configuration
   
   build:
     # use the same syntax as for dev to setup container:
     # environment
     # links
     # ... 
     commands:
       - bundle exec db:schema:load
       - bundle exec rspec
```
Then build, test and push your container usign command:

```
  export DOCKER_REGISTRY_PASSWORD=il0vedock<3r
  export DOCKER_REGISTRY_USERNAME=despictable-me
  export DOCKER_REGISTRY_EMAIL=me@despictable.me
  
  d --build TAG [BUILD_ID]
```

This command does:

1. build local image using ```dockerfile``` and tags it by provided ```TAG``` argument
2. start all the ```links``` containers, using ```BUILD_ID``` suffix (to not collide with concurrent tests)
3. for each ```commands``` run container using built image.
4. if all commands are successful, pushes image to docker registry using given credentials
5. in any case clean up all built images and remove all link containers

### Jenkins

To use fidoci with Jenkins, just install docker on your jenkins nodes and add ```jenkins``` user to ```docker``` group

```shell
   useradd -G docker jenkins
```

Configure test command to output JUnit XML file to output dir and mount that dir into the container

```yaml
  # ...
  volumes:
    - ./build_out:/root/app/build_out
  commands:
    - run_test -o build_out/test.xml
```

The whole build script can be simple as this:
```shell  
  mkdir -p build_out
  
  export DOCKER_REGISTRY_PASSWORD=...
  export DOCKER_REGISTRY_USERNAME=...
  export DOCKER_REGISTRY_EMAIL=...
  
  d --build $GIT_COMMIT $BUILD_TAG
```

## d.yml syntax

- ```image``` - [string] name of the app docker image in format repository/name
- ```dev``` - [object] describing development container
  - ```dockerfile``` - [string, optional] path to dockerfile used for building docker image
  - ```environment``` - [object, optional] of environment variables (as keys) and values (as values)
  - ```environment_pass``` - [list of strings, optional] of names of environment variables to copy from host to container
  - ```volumes``` - [list of strings, optional] list of mounted volumes in container. Format "host_path:container_path". Host path is expanded - ie it can use "."
  - ```ports``` - [list of strings, optional] list of propagated ports. Format "[host_ip:]host_port:container_port"
  - ```links``` - [object, optional] describtion of connected service containers to link to main container. Keys are used to alias link in docker.
    - ```image``` - [string] name of image to run container from. Format "[[registry/]repo/]image[:tag]"
    - ```environment```, ```environment_pass```, ```volumes```, ```ports``` - same as above
    - ```shared``` - [string, optional] name of container to use. if conainer with such name is present in host, it will start and link that. It will not stop container on exit. 
- ```build``` - [object] describing build container. It has the same syntax as ```dev```, only addition is
  - ```commands``` - [list of string] list of commands to run in that order to perform test. 
  - 
  
## TODO

- tests
- 

## Contributing

1. Fork the repository
2. Make changes
3. Create pull request and explain use case

Happy containerizing!
