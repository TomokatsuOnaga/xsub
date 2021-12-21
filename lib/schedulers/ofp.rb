require File.expand_path(File.dirname(__FILE__)+'/../scheduler')

module Xsub

  class Ofp < Scheduler

    TEMPLATE = <<EOS
#!/bin/bash -x
#
#PJM -L "node=<%= node %>"
#PJM -L "rscgrp=<%= Ofp.rscgrpname(node, elapse, memory_config) %>"
#PJM -L "elapse=<%= elapse %>"
#PJM -g "<%= Ofp.group%>"
#PJM --mpi "proc=<%= mpi_procs %>"
#PJM --mpi "max-proc-per-node=<%= max_mpi_procs_per_node %>"
#PJM -s

. <%= _job_file %>
EOS

    PARAMETERS = {
      'mpi_procs' => { description: 'MPI process', default: 1, format: '^[1-9]\d*$' },
      'max_mpi_procs_per_node' => { description: 'Max MPI processes per node', default: 1, format: '^[1-9]\d*$' },
      'omp_threads' => { description: 'OMP threads', default: 1, format: '^[1-9]\d*$' },
      'elapse' => { description: 'Limit on elapsed time', default: '1:00:00', format: '^\d+:\d{2}:\d{2}$' },
      'node' => { description: 'Nodes', default: '1', format: '^\d+(x\d+){0,2}$' },
      'memory_config' => { description: 'Use MCDRAM as cache?', default: 'flat', format: '^(flat|cache)$' }
    }

    def self.rscgrpname(node, elapse, memory_config)
      num_nodes = node.to_i
      elapse_time_sec = elapse.split(':').map(&:to_i).inject {|result, value| result * 60 + value}
      if memory_config == 'flat'
        if num_nodes <= 128 && elapse_time_sec <= 1800 # (1/2 hour)
          'debug-flat'
        else
          'regular-flat'
        end
      else
        if num_nodes <= 128 && elapse_time_sec <= 1800 # (1/2 hour)
          'debug-cache'
        else
          'regular-cache'
        end
      end
    end

    def self.group
      # On OFP, it is necessary to specify the "group" to which the user submitting the job belongs to
      # This is done using the environment variable "GROUP". export this variable in .bash_profile.
      # If your group is "gp43", your bash_profile should look something like this:
      ## # XSUB setup
      ## export XSUB_TYPE="ofp"
      ## export GROUP="myGroup"
      ## PATH=$PATH:$HOME/.local/bin:$HOME/bin:$HOME/xsub/bin
      ## export PATH

      ENV['GROUP']
    end

    def validate_parameters(parameters)
      num_procs = parameters['mpi_procs'].to_i
      num_threads = parameters['omp_threads'].to_i
      raise 'mpi_procs and omp_threads must be larger than or equal to 1' unless num_procs >= 1 and num_threads >= 1

#      node_values = parameters['node'].split('x').map(&:to_i)
#      shape_values = parameters['shape'].split('x').map(&:to_i)
#      raise 'node and shape must be a same format like node=>4x3, shape=>1x1' unless node_values.length == shape_values.length
#      raise 'each # in shape must be smaller than the one of node' unless node_values.zip(shape_values).all? {|node, shape| node >= shape}

      max_num_procs_per_node = parameters['max_mpi_procs_per_node'].to_i
      raise 'max_mpi_procs_per_node times omp_threads must be less than or equal to 68' unless max_num_procs_per_node * num_threads <= 68

#      max_num_procs = shape_values.inject(:*) * max_num_procs_per_node
#      raise "mpi_procs must be less than or equal to #{max_num_procs}" unless num_procs <= max_num_procs

#      low_priority_job = parameters['low_priority_job']
#      raise 'low_priority_job must be "true" or "false"' unless ['true', 'false'].include?(low_priority_job)
    end

    def submit_job(script_path, work_dir, log_dir, log, parameters)
      stdout_path = File.join( File.expand_path(log_dir), '%j.o.txt')
      stderr_path = File.join( File.expand_path(log_dir), '%j.e.txt')
      job_stat_path = File.join( File.expand_path(log_dir), '%j.i.txt')

      command = "cd #{File.expand_path(work_dir)} && pjsub #{File.expand_path(script_path)} -o #{stdout_path} -e #{stderr_path} --spath #{job_stat_path} < /dev/null"
      log.puts "cmd: #{command}"
      output = `#{command}`
      unless $?.success?
        log.puts "rc is not zero: #{output}"
        raise "rc is not zero: #{output}"
      end

      _, job_id = */Job (\d+) submitted/.match(output)
      unless job_id
        log.puts "failed to get job_id: #{output}"
        raise "failed to get job_id: #{output}"
      end

      log.puts "job_id: #{job_id}"
      { job_id: job_id, raw_output: output.lines.map(&:chomp) }
    end

    def parse_status(line)
      status =
        if line
          case line.split[2]
          when /QUEUED/
            :queued
          when /RUNNING/
            :running
          else
            :finished
          end
        else
          :finished
        end
      { :status => status, :raw_output => [line] }
    end

    def status(job_id)
      output = `pjstat #{job_id}`
      if $?.success?
        parse_status(output.lines.grep(/^\s*#{job_id}/).last)
      else
        { :status => :finished, :raw_output => output }
      end
    end

#    def multiple_status(job_id_list)
#      output_list = `pjstat`.split(/\R/)
#      job_id_list.map {|job_id| [job_id, parse_status(output_list.grep(/^s*#{job_id}/).last)]}.to_h
#    end

    def all_status
      `pjstat`
    end

    def delete(job_id)
      output = `pjdel #{job_id}`
      raise "pjdel failed: rc=#{$?.to_i}" unless $?.success?
      output
    end
  end
end
