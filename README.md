# Gjallarhorn

Multi-cloud deployment guardian as legendary as Heimdall's horn.

A Ruby gem that sounds across all cloud realms with secure, API-first deployments beyond SSH. Currently supporting AWS with additional providers planned for future releases.

## Features

**Phase 1 (0.1.0) - AWS Foundation:**
- ✅ AWS SSM-based deployments (no SSH required)
- ✅ Thor-based CLI with comprehensive commands
- ✅ YAML configuration system
- ✅ Comprehensive test coverage
- ✅ Complete YARD documentation

**Future Phases:**
- Google Cloud Platform (Compute Engine API)
- Microsoft Azure (Run Command API)
- Self-hosted Docker (Docker API)
- Kubernetes (API)
- Hybrid/Multi-cloud deployments

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add gjallarhorn
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install gjallarhorn
```

## Usage

### Configuration

Create a `deploy.yml` file in your project root:

```yaml
production:
  provider: aws
  region: us-west-2
  services:
    - name: web
      ports: ["80:8080"]
      env:
        RAILS_ENV: production
        DATABASE_URL: postgresql://user:pass@host/db

staging:
  provider: aws
  region: us-west-2
  services:
    - name: web
      ports: ["80:8080"]
      env:
        RAILS_ENV: staging
```

### CLI Commands

Deploy to an environment:
```bash
gjallarhorn deploy production myapp:v1.2.3
```

Check deployment status:
```bash
gjallarhorn status production
```

Rollback to previous version:
```bash
gjallarhorn rollback production v1.2.2
```

View configuration:
```bash
gjallarhorn config
```

Show version:
```bash
gjallarhorn version
```

### AWS Prerequisites

Ensure your EC2 instances have:
- SSM Agent installed and running
- Appropriate IAM roles for SSM access
- Tags: `Environment` (e.g., "production") and `Role` (e.g., "web", "app")
- Docker installed and running

#### Required IAM Permissions

Your EC2 instances need an IAM role with the following permissions:

**For SSM access:**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:UpdateInstanceInformation",
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        }
    ]
}
```

**For ECR access (when deploying from ECR):**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            "Resource": "*"
        }
    ]
}
```

You can use the AWS managed policy `AmazonSSMManagedInstanceCore` for SSM access, and create a custom policy for ECR access.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kanutocd/gjallarhorn. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/kanutocd/gjallarhorn/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Gjallarhorn project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/kanutocd/gjallarhorn/blob/main/CODE_OF_CONDUCT.md).
