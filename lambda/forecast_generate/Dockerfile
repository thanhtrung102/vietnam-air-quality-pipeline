# forecast_generate/Dockerfile
# Container image Lambda for PM2.5 SARIMA + Prophet forecasting.
#
# statsmodels + prophet + pandas + pyarrow together exceed the 250 MB Lambda zip
# limit, so this function is deployed as a container image via ECR.
#
# Build and push:
#   ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
#   REGION=ap-southeast-1
#   REPO=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/openaq-forecast-generate
#
#   aws ecr get-login-password --region $REGION | \
#     docker login --username AWS --password-stdin $REPO
#
#   docker build -t openaq-forecast-generate .
#   docker tag  openaq-forecast-generate:latest $REPO:latest
#   docker push $REPO:latest
#
# Then set terraform variable:
#   forecast_lambda_image_uri = "$REPO:latest"
# and re-run: terraform apply -target=aws_lambda_function.forecast_generate

FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .

# statsmodels + pandas + pyarrow — no C compiler needed (all manylinux wheels).
RUN pip install --no-cache-dir -r requirements.txt

COPY handler.py .

CMD ["handler.handler"]
