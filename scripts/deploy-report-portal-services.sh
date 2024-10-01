#!/bin/bash

AWS_ACCOUNT_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_ACCOUNT_ID)
AWS_REGION=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_REGION)
CLUSTER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .CLUSTER_NAME)

FAMILY=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.Family)
SERVICE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.ServiceName)
TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.TaskRole)
EXECUTION_TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.ExecutionTaskRole)
AWS_LOGS_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.AwsLogsGroup)

RABBITMQ_USER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.UserName)
RABBITMQ_PASSWORD=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.Password)

DATABASE_HOST=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Host)
DATABASE_PORT=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Port)
DATABASE_USER=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.User)
DATABASE_PASSWORD=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Password)
DATABASE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Name)

VOLUME_FILE_SYSTEM_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.Volume.Name)
VOLUME_FILE_SYSTEM_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .ReportPortalServices.Volume.FileSystemId)


CONTAINER_DEFINITION=$(jq -n \
    --arg aws_logs_group "$AWS_LOGS_GROUP" \
    --arg aws_region "$AWS_REGION" \
    --arg rabbitmq_user_name "$RABBITMQ_USER_NAME" \
    --arg rabbitmq_password "$RABBITMQ_PASSWORD" \
    --arg database_host "$DATABASE_HOST" \
    --arg database_port "$DATABASE_PORT" \
    --arg database_user "$DATABASE_USER" \
    --arg database_password "$DATABASE_PASSWORD" \
    --arg database_name "$DATABASE_NAME" \
    --arg volume_file_system_name "$VOLUME_FILE_SYSTEM_NAME" \
    '[
        {
            "name": "rabbitmq",
            "image": "bitnami/rabbitmq:3.13.7-debian-12-r2",
            "memory": 1024,
            "cpu": 512,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            },
            "environment": [
                {
                    "name": "RABBITMQ_DEFAULT_USER",
                    "value": "\($rabbitmq_user_name)"
                },
                {
                    "name": "RABBITMQ_DEFAULT_PASS",
                    "value": "\($rabbitmq_password)"
                },
                {
                    "name": "RABBITMQ_MANAGEMENT_ALLOW_WEB_ACCESS",
                    "value": "true"
                },
                {
                    "name": "RABBITMQ_PLUGINS",
                    "value": "rabbitmq_consistent_hash_exchange, rabbitmq_management, rabbitmq_auth_backend_ldap"
                }
            ],
            "healthCheck": {
                "command": ["CMD", "rabbitmqctl", "status"],
                "interval": 30,
                "timeout": 30,
                "retries": 5
            },
            "essential": true
        },

        {
            "name": "ui",
            "image": "reportportal/service-ui:5.12.0",
            "memory": 512,
            "cpu": 256,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            },
            "environment": [
                {
                "name": "RP_SERVER_PORT",
                "value": "8080"
                }
            ],
            "healthCheck": {
                "command": ["CMD-SHELL", "wget -q --spider http://0.0.0.0:8080/health || exit 1"],
                "interval": 30,
                "timeout": 30,
                "retries": 10,
                "startPeriod": 10
            },
            "essential": true,
            "dockerLabels": {
                "traefik.enable": "true",
                "traefik.http.middlewares.ui-strip-prefix.stripprefix.prefixes": "/ui",
                "traefik.http.routers.ui.middlewares": "ui-strip-prefix@ecs",
                "traefik.http.routers.ui.rule": "PathPrefix(`/ui`)",
                "traefik.http.routers.ui.service": "ui",
                "traefik.http.services.ui.loadbalancer.server.port": "8080",
                "traefik.http.services.ui.loadbalancer.server.scheme": "http",
                "traefik.expose": "true"
            }
        },

        {
            "name": "api",
            "image": "reportportal/service-api:5.12.0",
            "memory": 1024,
            "cpu": 512,
            "portMappings": [
                {
                "containerPort": 8585,
                "hostPort": 8585,
                "protocol": "tcp"
                }
            ],
            "environment": [
                { "name": "RP_DB_HOST", "value": "\($database_host)" },
                { "name": "RP_DB_USER", "value": "\($database_user)" },
                { "name": "RP_DB_PORT", "value": "\($database_port)" },
                { "name": "RP_DB_PASS", "value": "\($database_password)" },
                { "name": "RP_DB_NAME", "value": "\($database_name)" },
                { "name": "RP_AMQP_HOST", "value": "0.0.0.0" },
                { "name": "RP_AMQP_PORT", "value": "5672" },
                { "name": "RP_AMQP_APIPORT", "value": "15672" },
                { "name": "RP_AMQP_USER", "value": "\($rabbitmq_user_name)" },
                { "name": "RP_AMQP_PASS", "value": "\($rabbitmq_password)" },
                { "name": "RP_AMQP_APIUSER", "value": "\($rabbitmq_user_name)" },
                { "name": "RP_AMQP_APIPASS", "value": "\($rabbitmq_password)" },
                { "name": "RP_AMQP_ANALYZER-VHOST", "value": "analyzer" },
                { "name": "DATASTORE_TYPE", "value": "filesystem" },
                { "name": "LOGGING_LEVEL_ORG_HIBERNATE_SQL", "value": "info" },
                { "name": "RP_REQUESTLOGGING", "value": "true" },
                { "name": "AUDIT_LOGGER", "value": "OFF" },
                { "name": "MANAGEMENT_HEALTH_ELASTICSEARCH_ENABLED", "value": "false" },
                { "name": "RP_ENVIRONMENT_VARIABLE_ALLOW_DELETE_ACCOUNT", "value": "false" },
                { "name": "RP_JOBS_BASEURL", "value": "http://0.0.0.0:8686" },
                { "name": "COM_TA_REPORTPORTAL_JOB_INTERRUPT_BROKEN_LAUNCHES_CRON", "value": "PT1H" },
                { "name": "RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_BATCH-SIZE", "value": "100" },
                { "name": "RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_PREFETCH-COUNT", "value": "1" },
                { "name": "RP_ENVIRONMENT_VARIABLE_PATTERN-ANALYSIS_CONSUMERS-COUNT", "value": "1" },
                { "name": "JAVA_OPTS", "value": "-Xmx1g -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp -Dcom.sun.management.jmxremote.rmi.port=12349 -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.port=9010 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=0.0.0.0" },
                { "name": "COM_TA_REPORTPORTAL_JOB_LOAD_PLUGINS_CRON", "value": "PT10S" },
                { "name": "COM_TA_REPORTPORTAL_JOB_CLEAN_OUTDATED_PLUGINS_CRON", "value": "PT10S" },
                { "name": "REPORTING_QUEUES_COUNT", "value": "10" },
                { "name": "REPORTING_CONSUMER_PREFETCHCOUNT", "value": "10" },
                { "name": "REPORTING_PARKINGLOT_TTL_DAYS", "value": "7" }
            ],
            "dockerLabels": {
                "traefik.enable": "true",
                "traefik.http.middlewares.api-strip-prefix.stripprefix.prefixes": "/api",
                "traefik.http.routers.api.middlewares": "api-strip-prefix@ecs",
                "traefik.http.routers.api.rule": "PathPrefix(`/api`)",
                "traefik.http.routers.api.service": "api",
                "traefik.http.services.api.loadbalancer.server.port": "8585",
                "traefik.http.services.api.loadbalancer.server.scheme": "http",
                "traefik.expose": "true"
            },
            "mountPoints": [
                {
                    "sourceVolume": "\($volume_file_system_name)",
                    "containerPath": "/data/storage"
                }
            ],
            "healthCheck": {
                "command": [
                "CMD-SHELL",
                "curl -f http://0.0.0.0:8585/health || exit 1"
                ],
                "interval": 60,
                "timeout": 30,
                "retries": 10,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            },
            "dependsOn": [
                {
                    "containerName": "rabbitmq",
                    "condition": "HEALTHY"
                }
            ]
        },

        {
            "name": "uat",
            "image": "reportportal/service-authorization:5.12.0",
            "memory": 1024,
            "cpu": 512,
            "portMappings": [
                {
                "containerPort": 9999,
                "hostPort": 9999,
                "protocol": "tcp"
                }
            ],
            "environment": [
                { "name": "RP_DB_HOST", "value": "\($database_host)" },
                { "name": "RP_DB_USER", "value": "\($database_user)" },
                { "name": "RP_DB_PORT", "value": "\($database_port)" },
                { "name": "RP_DB_PASS", "value": "\($database_password)" },
                { "name": "RP_DB_NAME", "value": "\($database_name)" },
                { "name": "RP_AMQP_HOST", "value": "0.0.0.0" },
                { "name": "RP_AMQP_PORT", "value": "5672" },
                { "name": "RP_AMQP_APIPORT", "value": "15672" },
                { "name": "RP_AMQP_USER", "value": "\($rabbitmq_user_name)" },
                { "name": "RP_AMQP_PASS", "value": "\($rabbitmq_password)" },
                { "name": "RP_AMQP_APIUSER", "value": "\($rabbitmq_user_name)" },
                { "name": "RP_AMQP_APIPASS", "value": "\($rabbitmq_password)" },
                { "name": "DATASTORE_TYPE", "value": "filesystem" },
                { "name": "RP_SESSION_LIVE", "value": "86400" },
                { "name": "RP_SAML_SESSION-LIVE", "value": "4320" },
                { "name": "RP_INITIAL_ADMIN_PASSWORD", "value": "erebus" },
                { "name": "JAVA_OPTS", "value": "-Djava.security.egd=file:/dev/./urandom -XX:MinRAMPercentage=60.0 -XX:MaxRAMPercentage=90.0 --add-opens=java.base/java.lang=ALL-UNNAMED" }
            ],
            "dockerLabels": {
                "traefik.enable": "true",
                "traefik.http.middlewares.uat-strip-prefix.stripprefix.prefixes": "/uat",
                "traefik.http.routers.uat.middlewares": "uat-strip-prefix@ecs",
                "traefik.http.routers.uat.rule": "PathPrefix(`/uat`)",
                "traefik.http.routers.uat.service": "uat",
                "traefik.http.services.uat.loadbalancer.server.port": "9999",
                "traefik.http.services.uat.loadbalancer.server.scheme": "http",
                "traefik.expose": "true"
            },
            "mountPoints": [
                {
                    "sourceVolume": "\($volume_file_system_name)",
                    "containerPath": "/data/storage"
                }
            ],
            "healthCheck": {
                "command": [
                "CMD-SHELL",
                "curl -f http://0.0.0.0:9999/health || exit 1"
                ],
                "interval": 60,
                "timeout": 30,
                "retries": 10,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            },
            "dependsOn": [
                {
                    "containerName": "rabbitmq",
                    "condition": "HEALTHY"
                }
            ]
        },

        {
            "name": "jobs",
            "image": "reportportal/service-jobs:5.12.0",
            "memory": 1024,
            "cpu": 512,
            "portMappings": [
                {
                "containerPort": 8686,
                "hostPort": 8686,
                "protocol": "tcp"
                }
            ],
            "environment": [
                { "name": "RP_DB_HOST", "value": "\($database_host)" },
                { "name": "RP_DB_USER", "value": "\($database_user)" },
                { "name": "RP_DB_PORT", "value": "\($database_port)" },
                { "name": "RP_DB_PASS", "value": "\($database_password)" },
                { "name": "RP_DB_NAME", "value": "\($database_name)" },
                { "name": "RP_AMQP_HOST", "value": "0.0.0.0" },
                { "name": "RP_AMQP_PORT", "value": "5672" },
                { "name": "RP_AMQP_APIPORT", "value": "15672" },
                { "name": "RP_AMQP_USER", "value": "\($rabbitmq_user_name)" },
                { "name": "RP_AMQP_PASS", "value": "\($rabbitmq_password)" },
                { "name": "RP_AMQP_APIUSER", "value": "\($rabbitmq_user_name)" },
                { "name": "RP_AMQP_APIPASS", "value": "\($rabbitmq_password)" },
                { "name": "RP_ENVIRONMENT_VARIABLE_CLEAN_ATTACHMENT_CRON", "value": "0 0 */24 * * *" },
                { "name": "RP_ENVIRONMENT_VARIABLE_CLEAN_LOG_CRON", "value": "0 0 */24 * * *" },
                { "name": "RP_ENVIRONMENT_VARIABLE_CLEAN_LAUNCH_CRON", "value": "0 0 */24 * * *" },
                { "name": "RP_ENVIRONMENT_VARIABLE_STORAGE_PROJECT_CRON", "value": "0 */5 * * * *" },
                { "name": "RP_ENVIRONMENT_VARIABLE_CLEAN_EXPIREDUSER_RETENTIONPERIOD", "value": "365" },
                { "name": "RP_ENVIRONMENT_VARIABLE_NOTIFICATION_EXPIREDUSER_CRON", "value": "0 0 */24 * * *" },
                { "name": "RP_PROCESSING_LOG_MAXBATCHSIZE", "value": "2000" },
                { "name": "RP_PROCESSING_LOG_MAXBATCHTIMEOUT", "value": "6000" }
            ],
            "dockerLabels": {
                "traefik.enable": "true",
                "traefik.http.middlewares.jobs-strip-prefix.stripprefix.prefixes": "/jobs",
                "traefik.http.routers.jobs.middlewares": "jobs-strip-prefix@ecs",
                "traefik.http.routers.jobs.rule": "PathPrefix(`/jobs`)",
                "traefik.http.routers.jobs.service": "jobs",
                "traefik.http.services.jobs.loadbalancer.server.port": "8686",
                "traefik.http.services.jobs.loadbalancer.server.scheme": "http",
                "traefik.expose": "true"
            },
            "mountPoints": [
                {
                    "sourceVolume": "\($volume_file_system_name)",
                    "containerPath": "/data/storage"
                }
            ],
            "healthCheck": {
                "command": [
                "CMD-SHELL",
                "curl -f http://0.0.0.0:8686/health || exit 1"
                ],
                "interval": 60,
                "timeout": 30,
                "retries": 10,
                "startPeriod": 60
            },
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            },
            "dependsOn": [
                {
                    "containerName": "rabbitmq",
                    "condition": "HEALTHY"
                }
            ]
        },

        {
            "name": "analyzer",
            "image": "reportportal/service-auto-analyzer:5.12.0-r1",
            "memory": 2048,
            "cpu": 1024,
            "environment": [
                { "name": "LOGGING_LEVEL", "value": "DEBUG" },
                { "name": "AMQP_EXCHANGE_NAME", "value": "analyzer-default" },
                { "name": "AMQP_VIRTUAL_HOST", "value": "analyzer" },
                { "name": "AMQP_URL", "value": "amqp://\($rabbitmq_user_name):\($rabbitmq_password)@0.0.0.0:5672" },
                { "name": "ES_HOSTS", "value": "http://opensearch:9200" },
                { "name": "ANALYZER_BINARYSTORE_TYPE", "value": "filesystem" }
            ],
            "mountPoints": [
                {
                    "sourceVolume": "\($volume_file_system_name)",
                    "containerPath": "/data/storage"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            },
            "dependsOn": [
                {
                    "containerName": "rabbitmq",
                    "condition": "HEALTHY"
                }
            ]
        }
    ]')

VOLUMES=$(jq -n \
    --arg volume_file_system_name "$VOLUME_FILE_SYSTEM_NAME" \
    --arg volume_file_system_id "$VOLUME_FILE_SYSTEM_ID" \
    '[
        {
            "name": "\($volume_file_system_name)",
            "efsVolumeConfiguration": {
                "fileSystemId": "\($volume_file_system_id)",
                "rootDirectory": "/"
            } 
        }
    ]')

aws ecs register-task-definition \
    --family "${FAMILY}" \
    --region "${AWS_REGION}" \
    --network-mode awsvpc \
    --requires-compatibilities FARGATE \
    --memory 8192 \
    --cpu 4096 \
    --task-role-arn "${TASK_ROLE}" \
    --execution-role-arn "${EXECUTION_TASK_ROLE}" \
    --container-definitions "${CONTAINER_DEFINITION}" \
    --volumes "${VOLUMES}"  > ./report_portal_services_register_task_definition_output.json

NEW_REVISION=$(cat ./report_portal_services_register_task_definition_output.json | jq  '.taskDefinition.revision')
NEW_TASK_DEFINITION=${FAMILY}:${NEW_REVISION}

aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${NEW_TASK_DEFINITION} --force-new-deployment --region ${AWS_REGION}

aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}
