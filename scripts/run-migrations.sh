#!/bin/bash

AWS_ACCOUNT_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_ACCOUNT_ID)
AWS_REGION=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_REGION)
CLUSTER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .CLUSTER_NAME)

FAMILY=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.Family)
SERVICE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.ServiceName)
TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.TaskRole)
EXECUTION_TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.ExecutionTaskRole)
AWS_LOGS_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.AwsLogsGroup)

SUBNET=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.Subnet)
SECURUTY_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Migrations.SecurityGroup)

DATABASE_HOST=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Host)
DATABASE_USER=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.User)
DATABASE_PASSWORD=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Password)
DATABASE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Database.Name)

CONTAINER_DEFINITION=$(jq -n \
    --arg aws_logs_group "$AWS_LOGS_GROUP" \
    --arg aws_region "$AWS_REGION" \
    --arg database_host "$DATABASE_HOST" \
    --arg database_user "$DATABASE_USER" \
    --arg database_password "$DATABASE_PASSWORD" \
    --arg database_name "$DATABASE_NAME" \
    '[
        {
            "name": "migrations",
            "image": "reportportal/migrations:5.11.1",
            "memory": 512,
            "cpu": 256,
            "environment": [
                {
                    "name": "POSTGRES_SERVER",
                    "value": "\($database_host)"
                },
                {
                    "name": "POSTGRES_PORT",
                    "value": "5432"
                },
                {
                    "name": "POSTGRES_DB",
                    "value": "\($database_name)"
                },
                {
                    "name": "POSTGRES_USER",
                    "value": "\($database_user)"
                },
                {
                    "name": "POSTGRES_PASSWORD",
                    "value": "\($database_password)"
                },
                {
                    "name": "OS_HOST",
                    "value": "opensearch"
                },
                {
                    "name": "OS_PORT",
                    "value": "9200"
                },
                {
                    "name": "OS_PROTOCOL",
                    "value": "http"
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
        }
    ]')

aws ecs register-task-definition \
    --family "${FAMILY}" \
    --region "${AWS_REGION}" \
    --network-mode awsvpc \
    --requires-compatibilities FARGATE \
    --memory 512 \
    --cpu 256 \
    --task-role-arn "${TASK_ROLE}" \
    --execution-role-arn "${EXECUTION_TASK_ROLE}" \
    --container-definitions "${CONTAINER_DEFINITION}" > ./open_search_register_task_definition_output.json

NEW_REVISION=$(cat ./open_search_register_task_definition_output.json | jq  '.taskDefinition.revision')
NEW_TASK_DEFINITION=${FAMILY}:${NEW_REVISION}

aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${NEW_TASK_DEFINITION} --force-new-deployment --region ${AWS_REGION}

aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}

aws ecs update-service \
  --cluster ${CLUSTER_NAME} \
  --service ${SERVICE_NAME} \
  --region ${AWS_REGION} \
  --desired-count 0
