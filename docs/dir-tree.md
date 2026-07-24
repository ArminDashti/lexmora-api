lexmora-api/
├── cmd/server/main.go              # Gin server entry and routes
├── internal/
│   ├── config/config.go            # Env-based configuration
│   ├── db/db.go                    # Postgres pool and migrations
│   ├── domain/models.go            # Domain types and instruction keys
│   ├── handler/                    # HTTP handlers
│   ├── middleware/auth.go          # JWT authentication middleware
│   ├── repository/                 # Postgres data access
│   └── service/                    # Business logic and OpenRouter client
├── migrations/                     # SQL up/down migrations
├── instructions/                   # Reference prompt templates
├── docs/                           # Project documentation
├── growth-log/                     # Evolving architecture and feature notes
├── .armin/docker-scripts/          # Primary local/server Docker deploy scripts + YAML
├── .deploy/docker/                 # Dockerfile, compose, legacy deploy scripts
├── run-on-docker-local.ps1         # Stub → .armin/docker-scripts/
├── run-on-docker-server.ps1        # Stub → .armin/docker-scripts/
├── .docker/stack.manifest.json     # Docker image tags and ports
├── go.mod                          # Go module definition
├── db.md                           # PostgreSQL table and enum reference
└── README.md                       # Setup and usage guide
