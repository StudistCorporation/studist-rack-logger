# 🪵 Studist Rack Logger

> Unified structured logging middleware for Rack applications

[![Gem Version](https://badge.fury.io/rb/studist-rack-logger.svg)](https://badge.fury.io/rb/studist-rack-logger)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0.0-ruby.svg)](https://www.ruby-lang.org/en/)

## 🚀 Installation

```ruby
gem 'studist-rack-logger'
```

## ⚡ Quick Start

```ruby
# Rack app
use Studist::Rack::Logger, app_id: 'my-service'

# Rails
config.middleware.use Studist::Rack::Logger, app_id: 'my-rails-app'
```

## 🔧 Configuration

```ruby
use Studist::Rack::Logger,
  app_id: 'my-service',
  format: :json,  # or :ltsv
  logger: Rails.logger,
  user_id_extractor: ->(env, req) { env['user.id'] },
  normalized_uri_extractor: ->(env, req) { normalize_path(req.path) }
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `app_id` | String | `"unknown"` | Service identifier |
| `format` | Symbol | `:json` | Log format (`:json` or `:ltsv`) |
| `logger` | Logger | `Logger.new($stdout)` | Logger instance |
| `log_version` | String | `"1.0.0"` | Log schema version |
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
- **Structured logs** - JSON/LTSV formats
- **Distributed tracing** - AWS X-Ray compatible
- **Custom extractors** - Flexible user/URI extraction
- **Error handling** - Logs exceptions with 500 status
- **Performance focused** - Minimal overhead

---

<div align="center">
Made with ❤️ by <a href="https://studist.jp">Studist</a>
</div>
