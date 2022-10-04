resource "aws_cloudwatch_metric_alarm" "WA-Lab-Dependency-test" {
    actions_enabled           = true
    alarm_actions             = [
        aws_sns_topic.sns_topic.arn
    ]
    alarm_name                = "WA-Lab-Dependency-Alarm"
    comparison_operator       = "LessThanThreshold"
    datapoints_to_alarm       = 1
    dimensions                = {
        "FunctionName" = "WA-Lab-DataReadFunction"
        "Resource"     = "WA-Lab-DataReadFunction"
    }
    evaluation_periods        = 1
    id                        = "WA-Lab-Dependency-Alarm"
    insufficient_data_actions = []
    metric_name               = "Invocations"
    namespace                 = "AWS/Lambda"
    ok_actions                = []
    period                    = 60
    statistic                 = "Sum"
    tags                      = {}
    tags_all                  = {}
    threshold                 = 1
    treat_missing_data        = "missing"
}
