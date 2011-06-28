require 'logger'
require 'socket'
require 'galaxy/host'

module Galaxy
    module Config
        DEFAULT_HOST = ENV["GALAXY_HOST"] || "localhost"
        DEFAULT_LOG = ENV["GALAXY_LOG"] || "SYSLOG"
        DEFAULT_LOG_LEVEL = ENV["GALAXY_LOG_LEVEL"] || "INFO"
        DEFAULT_MACHINE_FILE = ENV["GALAXY_MACHINE_FILE"] || ""
        DEFAULT_AGENT_PID_FILE = ENV["GALAXY_AGENT_PID_FILE"] || "/tmp/galaxy-agent.pid"
        DEFAULT_CONSOLE_PID_FILE = ENV["GALAXY_CONSOLE_PID_FILE"] || "/tmp/galaxy-console.pid"

        DEFAULT_PING_INTERVAL = 60

        def read_config_file config_file
            config_file = config_file || ENV['GALAXY_CONFIG']
            unless config_file.nil? or config_file.empty?
                msg = "Cannot find configuration file: #{config_file}"
                unless File.exist?(config_file)
                    raise msg
                end
            end
            config_files = [config_file, '/etc/galaxy.conf', '/usr/local/etc/galaxy.conf'].compact
            config_files.each do |file|
                begin
                    File.open file, "r" do |f|
                        return YAML.load(f.read)
                    end
                rescue Errno::ENOENT
                end
            end
            # Fall through to empty config hash
            return {}
        end

        def set_machine machine_from_file
            @machine ||= @config.machine || machine_from_file
        end

        def set_pid_file pid_file_from_file
            @pid_file ||= @config.pid_file || pid_file_from_file
        end

        def set_user user_from_file
            @user ||= @config.user || user_from_file || nil
        end

        def set_verbose verbose_from_file
            @verbose ||= @config.verbose || verbose_from_file
        end

        def set_log log_from_file
            @log ||= @config.log || log_from_file || DEFAULT_LOG
            begin
                # Check if we can log to it
                test_logger = Galaxy::Log::Glogger.new(@log)
                # Make sure to reap file descriptors (except STDOUT/STDERR/SYSLOG)
                test_logger.close unless @log == "STDOUT" or @log == "STDERR" or @log == "SYSLOG"
            rescue
                # Log exception to syslog
                syslog_log $!
                raise $!
            end

            return @log
        end

        def set_log_level log_level_from_file
            @log_level ||= begin
                log_level = @config.log_level || log_level_from_file || DEFAULT_LOG_LEVEL
                case log_level
                    when "DEBUG"
                        Logger::DEBUG
                    when "INFO"
                        Logger::INFO
                    when "WARN"
                        Logger::WARN
                    when "ERROR"
                        Logger::ERROR
                end
            end
        end

        def guess key
            val = self.send key
            puts "    --#{correct key} #{val}" if @config.verbose
            val
        end

        def syslog_log e
            Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.warning e }
        end

        module_function :read_config_file, :set_machine, :set_pid_file, :set_verbose,
                        :set_log, :set_log_level, :set_user, :guess
    end

    class ConsoleConfigurator
        include Config

        def initialize config
            @config = config
            @config_from_file = read_config_file(config.config_file)
        end

        def correct key
            case key
                # Console
                when :announcement_url
                    "announcement-url"
                when :ping_interval
                    "ping-interval"
                when :console_proxied_url
                    "console-proxied-url"
                when :console_log
                    "console-log"

                # Shared opts
                when :log_level
                    "log-level"
                when :config_file
                    "config"
                else
                    key
            end
        end

        def configure
            puts "startup configuration" if @config.verbose
            {
                :environment => guess(:environment),
                :verbose => guess(:verbose),
                :log => guess(:log),
                :log_level => guess(:log_level),
                :pid_file => guess(:pid_file),
                :user => guess(:user),
                :host => guess(:host),
                :announcement_url => guess(:announcement_url),
                :ping_interval => guess(:ping_interval),
                :console_proxied_url => guess(:console_proxied_url),
            }
        end

        def console_proxied_url
            return @config.console_proxied_url
        end

        def verbose
            set_verbose @config_from_file['galaxy.agent.verbose']
        end

        def log
            set_log @config_from_file['galaxy.console.log']
        end

        def log_level
            set_log_level @config_from_file['galaxy.console.log-level']
        end

        def pid_file
            set_pid_file @config_from_file['galaxy.console.pid-file'] ||
                DEFAULT_CONSOLE_PID_FILE
        end

        def user
            set_user @config_from_file['galaxy.console.user']
        end

        def announcement_url
            @announcement_url ||= @config.announcement_url || @config_from_file['galaxy.console.announcement-url'] || "http://#{`hostname`.strip}"
        end

        def host
            @host ||= @config.host || @config_from_file['galaxy.console.host'] || begin
                Socket.gethostname rescue DEFAULT_HOST
            end
        end

        def ping_interval
            @ping_interval ||= @config.ping_interval || @config_from_file['galaxy.console.ping-interval'] || 60
            @ping_interval = @ping_interval.to_i
        end

        def environment
            @env ||= begin
                if @config.environment
                    @config.environment
                elsif @config_from_file['galaxy.console.environment']
                    @config_from_file['galaxy.console.environment']
                end
            end
        end
    end
end
