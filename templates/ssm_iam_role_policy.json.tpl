{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Action":[
                "ssm:DescribeParameters",
                "ssm:GetParameter",
                "ssm:GetParameters"
            ],
            "Resource": [
                "${ssm_parameter_arn}/*"
            ]
        }
    ]
}