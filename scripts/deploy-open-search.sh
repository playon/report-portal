#!/bin/bash

AWS_ACCOUNT_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_ACCOUNT_ID)
AWS_REGION=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .AWS_REGION)
CLUSTER_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .CLUSTER_NAME)
FAMILY=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.Family)
SERVICE_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.ServiceName)
TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.TaskRole)
EXECUTION_TASK_ROLE=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.ExecutionTaskRole)
AWS_LOGS_GROUP=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.AwsLogsGroup)
FILE_SYSTEM_NAME=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.Volume.Name)
FILE_SYSTEM_ID=$(cat ./configs/vars-${ENVIRONMENT}.json | jq -r .OpenSearch.Volume.FileSystemId)

CONTAINER_DEFINITION=$(jq -n \
    --arg aws_logs_group "$AWS_LOGS_GROUP" \
    --arg aws_region "$AWS_REGION" \
    '[
        {
        "name": "opensearch",
        "image": "opensearchproject/opensearch:2.16.0",
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "\($aws_logs_group)",
                "awslogs-region": "\($aws_region)",
                "awslogs-stream-prefix": "ecs"
            }        
        },
        "environment": [
            {"name": "discovery.type", "value": "single-node"},
            {"name": "plugins.security.disabled", "value": "true"},
            {"name": "bootstrap.memory_lock", "value": "true"},
            {"name": "OPENSEARCH_JAVA_OPTS", "value": "-Xms512m -Xmx512m"},
            {"name": "DISABLE_INSTALL_DEMO_CONFIG", "value": "true"},
            {"name": "node.max_local_storage_nodes", "value": "2"}
        ],
        "ulimits": [
            {
            "name": "memlock",
            "softLimit": -1,
            "hardLimit": -1
            }
        ],
        "mountPoints": [
            {
                "sourceVolume": "opensearch",
                "containerPath": "/usr/share/opensearch/data"
            }
        ],
        "healthCheck": {
            "command": ["CMD-SHELL", "curl -s -f http://localhost:9200/_cat/health"],
            "interval": 30,
            "timeout": 5,
            "retries": 3,
            "startPeriod": 10
        },
        "portMappings": [
            {
                "name": "opensearch-port",
                "containerPort": 9200,
                "hostPort": 9200,
                "protocol": "tcp"
            },
            {
                "containerPort": 9600,
                "hostPort": 9600,
                "protocol": "tcp"
            }
        ],
        "essential": true
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
    --memory 2048 \
    --cpu 1024 \
    --task-role-arn "${TASK_ROLE}" \
    --execution-role-arn "${EXECUTION_TASK_ROLE}" \
    --container-definitions "${CONTAINER_DEFINITION}" \
    --volumes "${VOLUMES}"  > ./open_search_register_task_definition_output.json

NEW_REVISION=$(cat ./open_search_register_task_definition_output.json | jq  '.taskDefinition.revision')
NEW_TASK_DEFINITION=${FAMILY}:${NEW_REVISION}

aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${NEW_TASK_DEFINITION} --force-new-deployment --region ${AWS_REGION}

aws ecs wait services-stable --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION}
