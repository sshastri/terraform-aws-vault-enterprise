{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Action":[
                "ssm:DescribeParameters",
                "ssm:GetParameters"
            ],
            "Resource": [
                "arn:aws:ssm:${aws_region}:${account_id}:parameter/${ssm_base_path}/vault/*"
            ]
        }
    ]
}
