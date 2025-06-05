# 🪵 Studist Rack Logger

> Unified structured logging middleware for Rack applications

[![Gem Version](https://badge.fury.io/rb/studist-rack-logger.svg)](https://badge.fury.io/rb/studist-rack-logger)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0.0-ruby.svg)](https://www.ruby-lang.org/en/)

## 🚀 Installation

```ruby
gem 'studist-rack-logger'
```

## ⚡ Quick Start

### Simple Usage
```ruby
# Rack app
use Studist::Rack::Logger, app_id: 'my-service'

# Rails
config.middleware.use Studist::Rack::Logger, app_id: 'my-rails-app'
```

### Configuration DSL (Recommended)
```ruby
# Configure once, use everywhere
Studist::Rack::Logger.configure do |config|
  config.app_id = 'my-service'
  config.format = :json
  config.sampling_rate = 0.1  # Log 10% of requests
  config.skip_paths = %w[/health /metrics]
  config.extractor(:user_id) { |env, req| env['user.id'] }
end

# Then use without options
use Studist::Rack::Logger
```

## 🔧 Configuration

### Configuration DSL (Recommended)

```ruby
Studist::Rack::Logger.configure do |config|
  # Basic settings
  config.app_id = 'my-service'
  config.format = :json  # or :ltsv
  config.logger = Rails.logger
  config.log_version = '2.0.0'
  
  # Performance options
  config.sampling_rate = 0.1          # Log 10% of requests
  config.error_sampling_rate = 1.0     # Always log errors
  
  # Filtering
  config.skip_paths = %w[/health /metrics /ping]
  config.skip_if { |context| context[:status] == 200 && context[:request_path].start_with?('/assets') }
  
  # Custom extractors
  config.extractor(:user_id) { |env, req| env['user.id'] }
  config.extractor(:user_group_id) { |env, req| env['user.group'] }
  config.extractor(:user_authority) { |env, req| env['user.role'] }
  config.extractor(:normalized_uri) { |env, req| normalize_path(req.path) }
  
  # Custom filters
  config.filter { |context| context[:status] != 404 }
end

use Studist::Rack::Logger
```

### Hash-based Configuration (Legacy)

```ruby
use Studist::Rack::Logger,
  app_id: 'my-service',
  format: :json,
  logger: Rails.logger,
  sampling_rate: 0.1,
  user_id_extractor: ->(env, req) { env['user.id'] },
  normalized_uri_extractor: ->(env, req) { normalize_path(req.path) }
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app_id` | String | `"unknown"` | Service identifier |
| `format` | Symbol | `:json` | Log format (`:json` or `:ltsv`) |
| `logger` | Logger | `Logger.new($stdout)` | Logger instance |
| `log_version` | String | `"1.0.0"` | Log schema version |
| `sampling_rate` | Float | `1.0` | Request sampling rate (0.0-1.0) |
| `error_sampling_rate` | Float | `1.0` | Error sampling rate (0.0-1.0) |
| `skip_paths` | Array | `[]` | Paths to skip logging |
| `user_id_extractor` | Proc | `nil` | Extract user ID from request |
| `user_group_id_extractor` | Proc | `nil` | Extract user group ID |
| `user_authority_extractor` | Proc | `nil` | Extract user authority |
| `normalized_uri_extractor` | Proc | `nil` | Extract normalized URI pattern |

## 📊 Log Fields

Outputs **18 standardized fields** including:

```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "app_id": "my-service",
  "trace_id": "Root=1-5e1b4151-...",
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "status_code": 200,
  "request_method": "GET",
  "request_url": "https://api.example.com/users/123",
  "response_time_ms": 42,
  "user_id": "user123",
  "remote_addr": "203.0.113.195"
}
```

<details>
<summary>View all fields</summary>

- `timestamp` - ISO8601 timestamp with milliseconds
- `log_version` - Log schema version  
- `app_id` - Application identifier
- `trace_id` - Distributed tracing ID
- `request_id` - Unique request ID (auto-generated)
- `server_name` - Hostname
- `status_code` - HTTP response status
- `request_method` - HTTP method
- `request_url` - Full request URL
- `request_body_size` - Request payload size in bytes
- `query_string` - URL query parameters
- `host` - Request host header
- `user_agent` - User agent string
- `referer` - HTTP referer header
- `remote_addr` - Client IP address
- `x_forwarded_for` - X-Forwarded-For header
- `normalized_uri` - URI pattern (via extractor)
- `response_time_ms` - Response time in milliseconds
- `response_body_size` - Response payload size
- `user_id` - User identifier (via extractor)
- `user_group_id` - User group (via extractor)
- `user_authority` - User role/authority (via extractor)

</details>

## 🎯 Features

- **Zero-config** - Works out of the box
- **Configuration DSL** - Powerful block-based configuration
- **Structured logs** - JSON/LTSV formats
- **Distributed tracing** - AWS X-Ray compatible
- **Custom extractors** - Flexible user/URI extraction
- **Advanced filtering** - Skip paths, conditions, and custom filters
- **Sampling support** - Separate rates for requests and errors
- **Error handling** - Logs exceptions with 500 status and backtrace
- **Performance optimized** - Hostname caching, efficient sampling
- **Production ready** - Safe fallbacks, never fails your app

## 🚀 Advanced Usage

### Sampling for High-Traffic Services

```ruby
Studist::Rack::Logger.configure do |config|
  config.app_id = 'high-traffic-api'
  config.sampling_rate = 0.01         # Log 1% of successful requests
  config.error_sampling_rate = 1.0     # Always log errors
end
```

### Conditional Logging

```ruby
Studist::Rack::Logger.configure do |config|
  config.app_id = 'my-service'
  
  # Skip health checks and assets
  config.skip_paths = %w[/health /ping /assets]
  
  # Skip successful admin requests
  config.skip_if do |context|
    context[:request_path].start_with?('/admin') && 
    context[:status] == 200
  end
  
  # Only log errors and slow requests
  config.filter do |context|
    context[:error] || context[:response_time_ms] > 1000
  end
end
```

### Custom Data Extraction

```ruby
Studist::Rack::Logger.configure do |config|
  # Extract user information
  config.extractor(:user_id) do |env, request|
    # From JWT token
    token = env['HTTP_AUTHORIZATION']&.sub(/^Bearer /, '')
    JWT.decode(token)&.dig(0, 'user_id') if token
  end
  
  # Extract tenant ID
  config.extractor(:tenant_id) do |env, request|
    request.headers['X-Tenant-ID'] || 
    request.subdomain
  end
  
  # Normalize API routes
  config.extractor(:normalized_uri) do |env, request|
    path = request.path
    path.gsub(/\/\d+/, '/:id')          # /users/123 → /users/:id
        .gsub(/\/[a-f0-9-]{36}/, '/:uuid') # UUIDs → :uuid
  end
end
```

### Rails Integration

```ruby
# config/application.rb
class Application < Rails::Application
  # Configure logger
  Studist::Rack::Logger.configure do |config|
    config.app_id = Rails.application.class.module_parent_name.downcase
    config.logger = Rails.logger
    config.sampling_rate = Rails.env.production? ? 0.1 : 1.0
    config.skip_paths = %w[/health /assets]
    
    # Extract user from Devise/session
    config.extractor(:user_id) do |env, request|
      env['warden']&.user&.id
    end
  end
  
  # Add middleware
  config.middleware.use Studist::Rack::Logger
end
```

## 🔄 Migration from Hash Configuration

### Before (Hash-based)
```ruby
use Studist::Rack::Logger,
  app_id: 'my-service',
  user_id_extractor: ->(env, req) { env['user.id'] },
  normalized_uri_extractor: ->(env, req) { normalize_path(req.path) }
```

### After (DSL)
```ruby
Studist::Rack::Logger.configure do |config|
  config.app_id = 'my-service'
  config.extractor(:user_id) { |env, req| env['user.id'] }
  config.extractor(:normalized_uri) { |env, req| normalize_path(req.path) }
end

use Studist::Rack::Logger
```

**Benefits of DSL:**
- Global configuration reuse
- Advanced filtering capabilities  
- Better validation and error messages
- More readable and maintainable
- Supports complex conditional logic

---

<div align="center">
Made with ❤️ by <a href="https://studist.jp">Studist</a>
</div>
