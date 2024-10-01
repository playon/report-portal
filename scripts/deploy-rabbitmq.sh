#!/bin/bash

AWS_ACCOUNT_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_ACCOUNT_ID)
AWS_REGION=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_REGION)
CLUSTER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .CLUSTER_NAME)

FAMILY=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.Family)
SERVICE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.ServiceName)
TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.TaskRole)
EXECUTION_TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.ExecutionTaskRole)
AWS_LOGS_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.AwsLogsGroup)

RABBITMQ_USER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.UserName)
RABBITMQ_PASSWORD=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .RabbitMQ.Password)

CONTAINER_DEFINITION=$(jq -n \
  --arg aws_logs_group "$AWS_LOGS_GROUP" \
  --arg aws_region "$AWS_REGION" \
  --arg rabbitmq_user_name "$RABBITMQ_USER_NAME" \
  --arg rabbitmq_password "$RABBITMQ_PASSWORD" \
  '[
        {
            "name": "rabbitmq",
            "image": "bitnami/rabbitmq:3.13.7-debian-12-r2",
            "memory": 1024,
            "cpu": 512,
            "portMappings": [
                {
                    "name": "rabbitmq-management-port",
                    "containerPort": 5672,
                    "hostPort": 5672
                },
                {
                    "name": "rabbitmq-api-port",
                    "containerPort": 15672,
                    "hostPort": 15672
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
    --container-definitions "${CONTAINER_DEFINITION}" > ./rabbitmq_register_task_definition_output.json

NEW_REVISION=$(cat ./rabbitmq_register_task_definition_output.json | jq  '.taskDefinition.revision')
NEW_TASK_DEFINITION=${FAMILY}:${NEW_REVISION}

aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${NEW_TASK_DEFINITION} --force-new-deployment --region ${AWS_REGION}

aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}
