#!/bin/bash

AWS_ACCOUNT_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_ACCOUNT_ID)
AWS_REGION=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_REGION)
CLUSTER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .CLUSTER_NAME)
LAMBDA_FUNCTION_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .LAMBDA_FUNCTION_NAME)

FAMILY=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.Family)
SERVICE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.ServiceName)
TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.TaskRole)
EXECUTION_TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.ExecutionTaskRole)
AWS_LOGS_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.AwsLogsGroup)

FILE_SYSTEM_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.Volume.Name)
FILE_SYSTEM_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .Traefik.Volume.FileSystemId)

CONTAINER_DEFINITION=$(jq -n \
  --arg aws_logs_group "$AWS_LOGS_GROUP" \
  --arg aws_region "$AWS_REGION" \
  --arg cluster_name "$CLUSTER_NAME" \
  '[
        {
            "name": "traefik",
            "image": "traefik:v2.4",
            "memory": 1024,
            "cpu": 512,
            "essential": true,
            "healthCheck": {
                "command": ["CMD-SHELL", "wget -q --spider http://0.0.0.0:8080/ping"],
                "interval": 30,
                "timeout": 30,
                "retries": 10,
                "startPeriod": 10
            },
            "portMappings": [
                {
                    "containerPort": 8080,
                    "hostPort": 8080
                },
                {
                    "containerPort": 8081,
                    "hostPort": 8081
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
            "mountPoints": [
                {
                    "sourceVolume": "docker_sock",
                    "containerPath": "/var/run/docker.sock"
                }
            ],
            "entryPoint": ["traefik"],
            "command": [
                "--providers.ecs=true",
                "--ping=true",
                "--ping.entrypoint=web",
                "--providers.ecs.region=\($aws_region)",
                "--providers.ecs.clusters=\($cluster_name)",
                "--providers.ecs.exposedByDefault=false",
                "--providers.ecs.refreshSeconds=60",
                "--entrypoints.web.address=:8080",
                "--entrypoints.traefik.address=:8081",
                "--api.dashboard=true",
                "--api.insecure=true",
                "--log.level=DEBUG",
                "--accesslog=true",
                "--accesslog.format=json"
            ]
        }
    ]')

VOLUMES=$(jq -n \
  --arg file_system_name "$FILE_SYSTEM_NAME" \
  --arg file_system_id "$FILE_SYSTEM_ID" \
  '[
        {
            "name": "\($file_system_name)",
            "efsVolumeConfiguration": {
                "fileSystemId": "\($file_system_id)",
                "rootDirectory": "/"
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
    --container-definitions "${CONTAINER_DEFINITION}" \
    --volumes "${VOLUMES}"  > ./open_search_register_task_definition_output.json

NEW_REVISION=$(cat ./open_search_register_task_definition_output.json | jq  '.taskDefinition.revision')
NEW_TASK_DEFINITION=${FAMILY}:${NEW_REVISION}

aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${NEW_TASK_DEFINITION} --force-new-deployment --region ${AWS_REGION}

aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}

aws ecs list-tasks \
    --cluster "${CLUSTER_NAME}"  \
    --service "${SERVICE_NAME}" \
    --region "${AWS_REGION}" > ./traefik_arn.json

TASK_ARN=$(cat ./traefik_arn.json | jq  '.taskArns[0]' --raw-output)

aws ecs describe-tasks \
    --cluster "${CLUSTER_NAME}" \
    --tasks ${TASK_ARN} \
    --region "${AWS_REGION}" > ./created_traefik_task.json

TRAEFIK_PRIVATE_IP=$(cat ./created_traefik_task.json | jq  '.tasks[0].attachments[0].details[] | select(.name=="privateIPv4Address") | .value' --raw-output)

aws lambda update-function-configuration \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --region "${AWS_REGION}" \
    --environment "Variables={TRAEFIK_SERVICES_URL=http://${TRAEFIK_PRIVATE_IP}:8081}"