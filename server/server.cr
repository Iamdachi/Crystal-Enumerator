require "http/server"
require "json"
require "file"

# Configuration
PORT = ENV["PORT"]?.try(&.to_i) || 8080
RESULTS_DIR = ENV["RESULTS_DIR"]? || "./linpeas_results"

# Create results directory if it doesn't exist
unless Dir.exists?(RESULTS_DIR)
  Dir.mkdir_p(RESULTS_DIR)
  puts "📁 Created results directory: #{RESULTS_DIR}"
end

# Request handler
server = HTTP::Server.new do |context|
  request = context.request
  response = context.response

  case {request.method, request.path}
  when {"POST", "/upload"}
    # Handle upload
    content_type = request.headers["Content-Type"]?
    if content_type && content_type.includes?("application/json")
      body = request.body.not_nil!.gets_to_end
      
      begin
        payload = JSON.parse(body).as_h
        
        hostname = payload["hostname"]?.try(&.as_s) || "unknown"
        timestamp = payload["timestamp"]?.try(&.as_s) || Time.utc.to_s
        results = payload["results"]?.try(&.as_s)
        
        if results && results.size > 0
          # Create filename based on hostname and timestamp
          timestamp_clean = timestamp.gsub(/[:\s]/, "_")
          filename = "#{hostname}_#{timestamp_clean}.txt"
          filepath = File.join(RESULTS_DIR, filename)
          
          # Save results to file
          File.write(filepath, results)
          
          puts "✅ Results received from #{hostname}"
          puts "📄 Saved to: #{filepath}"
          puts "📊 Size: #{results.size} bytes"
          
          response.status_code = 200
          response.content_type = "application/json"
          response.print({
            success: true,
            message: "Results received successfully",
            filename: filename,
            size: results.size
          }.to_json)
        else
          response.status_code = 400
          response.content_type = "application/json"
          response.print({error: "No results provided"}.to_json)
        end
      rescue ex
        puts "❌ Error processing upload: #{ex.message}"
        response.status_code = 500
        response.content_type = "application/json"
        response.print({error: "Internal server error"}.to_json)
      end
    else
      response.status_code = 400
      response.content_type = "application/json"
      response.print({error: "Content-Type must be application/json"}.to_json)
    end

  when {"GET", "/health"}
    # Health check
    response.status_code = 200
    response.content_type = "application/json"
    response.print({
      status: "ok",
      timestamp: Time.utc.to_s
    }.to_json)

  when {"GET", "/results"}
    # List results
    begin
      files = Dir.glob(File.join(RESULTS_DIR, "*.txt")).map { |f| File.basename(f) }
      response.status_code = 200
      response.content_type = "application/json"
      response.print({results: files}.to_json)
    rescue ex
      response.status_code = 500
      response.content_type = "application/json"
      response.print({error: "Failed to list results"}.to_json)
    end

  when {"GET", /^\/results\/(.+)$/}
    # Download specific result file
    match = request.path.match(/^\/results\/(.+)$/)
    filename = match[1] if match
    
    if filename
      filepath = File.join(RESULTS_DIR, filename)
      
      # Prevent directory traversal
      if !filepath.starts_with?(RESULTS_DIR) || filepath.includes?("..")
        response.status_code = 403
        response.content_type = "application/json"
        response.print({error: "Access denied"}.to_json)
      elsif File.exists?(filepath)
        response.status_code = 200
        response.content_type = "text/plain"
        response.headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
        response.print(File.read(filepath))
      else
        response.status_code = 404
        response.content_type = "application/json"
        response.print({error: "File not found"}.to_json)
      end
    else
      response.status_code = 404
      response.content_type = "application/json"
      response.print({error: "File not found"}.to_json)
    end

  else
    # 404 - Not Found
    response.status_code = 404
    response.content_type = "application/json"
    response.print({error: "Not found"}.to_json)
  end
end

# Bind server to port
address = server.bind_tcp("0.0.0.0", PORT)

puts "🚀 LinPEAS Results Server listening on port #{PORT}"
puts "📁 Results directory: #{RESULTS_DIR}"
puts "📤 Upload endpoint: http://localhost:#{PORT}/upload"
puts "📋 View results: http://localhost:#{PORT}/results"
puts "❤️  Health check: http://localhost:#{PORT}/health"
puts ""
puts "Press Ctrl+C to stop the server"

server.listen
