#Adding external services report to track FIRST hydra request 
DependencyDetection.defer do
  named :typhoeus_with_hydra

  depends_on do
    defined?(Typhoeus) && defined?(Typhoeus::VERSION)
  end

  depends_on do
    NewRelic::Agent::Instrumentation::TyphoeusTracing.is_supported_version?
  end

  depends_on do
    DependencyDetection.respond_to?(:banned_dependencies) && DependencyDetection.banned_dependencies.include?(:typhoeus)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Typhoeus instrumentation WITH hydra support'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/typhoeus_wrappers'
  end

  # Basic request tracing
  executes do
    Typhoeus.before do |request|
      NewRelic::Agent::Instrumentation::TyphoeusTracing.trace(request)

      # Ensure that we always return a truthy value from the before block,
      # otherwise Typhoeus will bail out of the instrumentation.
      true
    end
  end

  # Apply single TT node for Hydra requests until async support
  executes do
    #If this was run before, unchain first
    if Typhoeus::Hydra.hydra.respond_to?(:run_without_newrelic)
      class Typhoeus::Hydra
        alias run run_without_newrelic
      end
    end

    class Typhoeus::Hydra
      include NewRelic::Agent::MethodTracer
      attr_accessor :traced_request, :traced_request_lock

      def request_traced?
        self.traced_request_lock.synchronize do
          if  self.traced_request
            false
          else
            self.traced_request = true
            true
          end
        end
      end
      

      def run_with_newrelic(*args)
        self.traced_request_lock = Mutex.new
        self.traced_request = false
        trace_execution_scoped("External/Multiple/Typhoeus::Hydra/run") do
          run_without_newrelic(*args)
        end
      end

      alias run_without_newrelic run
      alias run run_with_newrelic
    end
  end
end


module NewRelic::Agent::Instrumentation::TyphoeusTracing

  EARLIEST_VERSION = NewRelic::VersionNumber.new("0.5.3")

  def self.is_supported_version?
    NewRelic::VersionNumber.new(Typhoeus::VERSION) >= NewRelic::Agent::Instrumentation::TyphoeusTracing::EARLIEST_VERSION
  end

  def self.request_is_hydra_enabled?(request)
    request.respond_to?(:hydra) && request.hydra
  end

  def self.trace(request)
    if NewRelic::Agent.is_execution_traced?
      if (request_is_hydra_enabled?(request) && request.hydra.request_traced?) || !request_is_hydra_enabled?(request)
        wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)
        t0, segment = ::NewRelic::Agent::CrossAppTracing.start_trace(wrapped_request)
        request.on_complete do
          wrapped_response = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(request.response)
          ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
        end if t0
      end
    end
  end
end
