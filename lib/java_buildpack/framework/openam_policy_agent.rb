# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013-2015 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/framework'
require 'java_buildpack/util/dash_case'
require 'tmpdir'
require 'fileutils'
require 'uri'

module JavaBuildpack
  module Framework

    # Encapsulates the detect, compile, and release functionality for enabling openam auto configuration.
    class OpenamPolicyAgent < JavaBuildpack::Component::VersionedDependencyComponent

      # Creates an instance
      #
      # @param [Hash] context a collection of utilities used the component
      def initialize(context)
        super(context)
        @server_url, @profile_name, @profile_password = supports? ? find_openam_agent : [nil, nil, nil]
      end

      def compile
         download_zip false
        @droplet.copy_resources
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
       # add_agent_configuration
      end

      protected

      def supports?
        @application.services.one_service? FILTER, 'server_url', 'profile_name', 'profile_password'
      end

    
      private

      FILTER = /openam/.freeze

      private_constant :FILTER

      def expand(file)
        with_timing "Expanding OpenAM J2EE Policy Agent to #{@droplet.sandbox.relative_path_from(@droplet.root)}" do
          Dir.mktmpdir do |root|
            agent_dir = unpack_agent_installer(Pathname.new(root), file)
            gen_password_and_response_file(agent_dir)
            install_openam(agent_dir)
          end
        end
      end

      def gen_response_file(agent_dir)
      VCAP_APPLICATION
      end
      
      def gen_password_and_response_file(agent_dir)

          File.open(password_file, 'w') { |f| f.write @profile_password }
         
          original = File.open(openam_response, 'r') { |f| f.read }

          # Remove any existing references 
          modified = original.gsub(/AM_SERVER_URL=.*$\n/, '')
          modified = original.gsub(/AGENT_URL=.*$\n/, '')
          modified = original.gsub(/AGENT_PROFILE_NAME=.*$\n/, '')

          # Add new references 
          modified << "AM_SERVER_URL= #{server_url}\n"
          modified << "AGENT_URL= https://#{application.details.uris[0]}/agentapp\n"
          modified << "AGENT_PROFILE_NAME= #{profile_name}\n"

          File.open(openam_response, 'w') { |f| f.write modified }
      end


      def unpack_agent_installer(root, file)
        agent_dir     = root + 'openam'
        FileUtils.mkdir_p(agent_dir)
        shell "unzip -qq #{file.path} -d #{agent_dir} 2>&1"
        agent_dir
      end

      def install_openam(agent_dir)
        agentadmin = agent_dir + '/j2ee_agents/tomcat_v6_agent/bin/agentadmin'
        shell "#{agentadmin} --install --acceptLicense --useResponse #{openam_response}"
      end

      def find_openam_agent
        service     = @application.services.find_service FILTER
        credentials = service['credentials']
        uri         = credentials['server_url']
        id          = credentials['profile_name']
        pass        = credentials['profile_password']
        [uri, id, pass]
      end

      def openam_directory
        @droplet.sandbox + 'openam/j2ee_agents/tomcat_v6_agent/Agent_001'
      end

      def logs_directory
        openam_directory + '/logs/debug'
      end

      def move(destination, *globs)
        FileUtils.mkdir_p destination

        globs.each do |glob|
          FileUtils.mv Pathname.glob(glob)[0], destination
        end
      end


    end
  end
end
