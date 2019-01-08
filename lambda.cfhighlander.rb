CfhighlanderTemplate do
  Name 'lambda'
  ComponentVersion component_version
  Description "#{component_name} - #{component_version}"

  functions.each do |function_name, lambda_config|
    if (lambda_config.has_key? 'enable_eni') && (lambda_config['enable_eni'])
      DependsOn 'vpc'
      break
    end
  end if defined? functions

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true, allowedValues: ['development', 'production']

    functions.each do |function_name, lambda_config|
      if (lambda_config.has_key? 'enable_eni') && (lambda_config['enable_eni'])
        ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
        maximum_availability_zones.times do |az|
          ComponentParam "SubnetCompute#{az}"
        end
        break
      end
    end if defined? functions

  end

end
