FROM alpine:latest

# Install bash and other dependencies your script needs (e.g., tar, curl)
RUN apk add --no-cache bash tar curl

WORKDIR /app

# Copy your script into the container
COPY build.sh .
RUN chmod +x build.sh

# Set the script as the entrypoint
ENTRYPOINT ["./build.sh"]