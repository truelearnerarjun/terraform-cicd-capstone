resource "aws_dynamodb_table" "terraform_locks" {
  name         = "group2-cicd-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "group2-cicd-terraform-locks"
  }
}
