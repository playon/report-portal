#!/bin/bash

AWS_ACCOUNT_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_ACCOUNT_ID)
AWS_REGION=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_REGION)
CLUSTER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .CLUSTER_NAME)

FAMILY=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .MetricsGatherer.Family)
SERVICE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .MetricsGatherer.ServiceName)
TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .MetricsGatherer.TaskRole)
EXECUTION_TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .MetricsGatherer.ExecutionTaskRole)
AWS_LOGS_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .MetricsGatherer.AwsLogsGroup)

RABBITMQ_USER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.UserName)
RABBITMQ_PASSWORD=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.Password)

DATABASE_HOST=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Host)
DATABASE_PORT=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Port)
DATABASE_USER=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.User)
DATABASE_PASSWORD=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Password)
DATABASE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Name)


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
    '[
        {
            "name": "metrics-gatherer",
            "image": "reportportal/service-metrics-gatherer:5.12.0-r1",
            "memory": 1024,
            "cpu": 512,
            "environment": [
                { "name": "LOGGING_LEVEL", "value": "DEBUG" },
                { "name": "ES_HOST", "value": "http://opensearch:9200" },
                { "name": "POSTGRES_USER", "value": "\($database_user)" },
                { "name": "POSTGRES_PASSWORD", "value": "\($database_password)" },
                { "name": "POSTGRES_DB", "value": "\($database_name)" },
                { "name": "POSTGRES_HOST", "value": "\($database_host)" },
                { "name": "POSTGRES_PORT", "value": "\($database_port)" },
                { "name": "ALLOWED_START_TIME", "value": "22:00" },
                { "name": "ALLOWED_END_TIME", "value": "08:00" },
                { "name": "AMQP_URL", "value": "amqp://\($rabbitmq_user_name):\($rabbitmq_password)@rabbitmq:5672" },
                { "name": "AMQP_VIRTUAL_HOST", "value": "analyzer" }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "\($aws_logs_group)",
                    "awslogs-region": "\($aws_region)",
                    "awslogs-stream-prefix": "ecs"
                }        
            }
        }
    ]')

aws ecs register-task-definition \
    --family "${FAMILY}" \
    --region "${AWS_REGION}" \
    --network-mode awsvpc \
    --requires-compatibilities FARGATE \
    --memory 1024 \
    --cpu 512 \
    --task-role-arn "${TASK_ROLE}" \
    --execution-role-arn "${EXECUTION_TASK_ROLE}" \
    --container-definitions "${CONTAINER_DEFINITION}" > ./metrics_gatherer_register_task_definition_output.json

NEW_REVISION=$(cat ./metrics_gatherer_register_task_definition_output.json | jq  '.taskDefinition.revision')
NEW_TASK_DEFINITION=${FAMILY}:${NEW_REVISION}

aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${NEW_TASK_DEFINITION} --force-new-deployment --region ${AWS_REGION}

aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}
