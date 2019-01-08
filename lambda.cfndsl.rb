CloudFormation do

  functions.each do |function_name, lambda_config|
    if (lambda_config.has_key? 'enable_eni') && (lambda_config['enable_eni'])
      az_conditions_resources('SubnetCompute', maximum_availability_zones)
      break
    end
  end if defined? functions

  tags = []
  tags << { Key: 'Environment', Value: Ref(:EnvironmentName) }
  tags << { Key: 'EnvironmentType', Value: Ref(:EnvironmentType) }

  extra_tags.each { |key,value| tags << { Key: key, Value: value } } if defined? extra_tags

  functions.each do |function_name, lambda_config|

    policies = []
    lambda_config['policies'].each do |name,policy|
      policies << iam_policy_allow(name,policy['action'],policy['resource'] || '*')
    end if lambda_config.has_key?('policies')

    IAM_Role("#{function_name}Role") do
      AssumeRolePolicyDocument service_role_assume_policy('lambda')
      Path '/'
      Policies policies if policies.any?
      ManagedPolicyArns lambda_config['managed_policies'] if lambda_config.has_key?('managed_policies')
    end

    if (lambda_config.has_key? 'enable_eni') && (lambda_config['enable_eni'])
      EC2_SecurityGroup("#{function_name}SecurityGroup") do
        GroupDescription FnSub("${EnvironmentName}-lambda-#{function_name}")
        VpcId Ref('VPCId')
        Tags tags
      end

      Output("#{function_name}SecurityGroup") {
        Value(Ref("#{function_name}SecurityGroup"))
        Export FnSub("${EnvironmentName}-#{component_name}-#{function_name}SecurityGroup")
      }
    end

    environment = lambda_config['environment'] || {}

    # Create Lambda function
    Lambda_Function(function_name) do
      Code({
          S3Bucket: distribution['bucket'],
          S3Key: FnSub("#{distribution['prefix']}/#{lambda_config['code_uri']}")
      })

      Environment(Variables: Hash[environment.collect { |k, v| [k, v] }])

      Handler(lambda_config['handler'] || 'index.handler')
      MemorySize(lambda_config['memory'] || 128)
      Role(FnGetAtt("#{function_name}Role", 'Arn'))
      Runtime(lambda_config['runtime'])
      Timeout(lambda_config['timeout'] || 10)
      if (lambda_config.has_key? 'enable_eni') && (lambda_config['enable_eni'])
        VpcConfig({
          SecurityGroupIds: [
            Ref("#{function_name}SecurityGroup")
          ],
          SubnetIds: az_conditional_resources('SubnetCompute', maximum_availability_zones)
        })
      end

      if !lambda_config['named'].nil? && lambda_config['named']
        FunctionName(function_name)
      end
      Tags tags
    end

    Logs_LogGroup("#{function_name}LogGroup") do
      LogGroupName FnSub("/aws/lambda/${function_name}")
      RetentionInDays lambda_config['log_retention'] if lambda_config.has_key? 'log_retention'
    end

    lambda_config['events'].each do |name,event|

      case event['type']
      when 'schedule'

        Events_Rule("#{function_name}Schedule#{name}") do
          ScheduleExpression event['expression']
          State event['disable'] ? 'DISABLED' : 'ENABLED'
          target = {
              Arn: FnGetAtt(function_name, 'Arn'),
              Id: "lambda#{function_name}"
          }
          target['Input'] = event['payload'] if event.key?('payload')
          Targets([target])
        end

        Lambda_Permission("#{function_name}#{name}Permissions") do
          FunctionName Ref(function_name)
          Action 'lambda:InvokeFunction'
          Principal 'events.amazonaws.com'
          SourceArn FnGetAtt("#{function_name}Schedule#{name}", 'Arn')
        end

      when 'sns'

        SNS_Topic("#{function_name}Sns#{name}") do
          Subscription([
            {
              Endpoint: FnGetAtt(function_name, 'Arn'),
              Protocol: 'lambda'
            }
          ])
        end

        Lambda_Permission("#{function_name}#{name}Permissions") do
          FunctionName Ref(function_name)
          Action 'lambda:InvokeFunction'
          Principal 'sns.amazonaws.com'
          SourceArn Ref("#{function_name}Sns#{name}")
        end

      when 'filter'

        Logs_SubscriptionFilter("#{function_name}SubscriptionFilter#{name}") do
          DestinationArn FnGetAtt(function_name, 'Arn')
          FilterPattern event['pattern']
          LogGroupName Ref(event['log_group'])
        end

        Lambda_Permission("#{function_name}#{name}Permissions") do
          FunctionName Ref(function_name)
          Action 'lambda:InvokeFunction'
          Principal FnSub('logs.${AWS::Region}.amazonaws.com')
          SourceAccount Ref('AWS::AccountId')
          SourceArn FnSub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/#{event['log_group']}:*")
        end

      end

    end if lambda_config.has_key?('events')

  end if defined? functions



end
