data "archive_file" "process_upload" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/process_upload"
  output_path = "${path.module}/build/process_upload.zip"
}

resource "aws_s3_object" "process_upload_package" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  key    = "process_upload/${data.archive_file.process_upload.output_md5}.zip"
  source = data.archive_file.process_upload.output_path
  etag   = data.archive_file.process_upload.output_md5
}

resource "aws_cloudwatch_log_group" "process_upload" {
  name              = "/aws/lambda/${var.environment_name}-process-upload"
  retention_in_days = 14
}

resource "aws_lambda_function" "process_upload" {
  function_name = "${var.environment_name}-process-upload"
  role          = aws_iam_role.lambda_process_upload.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  s3_bucket = aws_s3_bucket.lambda_artifacts.id
  s3_key    = aws_s3_object.process_upload_package.key

  source_code_hash = data.archive_file.process_upload.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda_process_upload.id]
  }

  environment {
    variables = {
      UPLOADS_BUCKET = aws_s3_bucket.uploads.id
    }
  }

  depends_on = [aws_cloudwatch_log_group.process_upload]
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_upload.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "uploads_trigger" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_upload.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
