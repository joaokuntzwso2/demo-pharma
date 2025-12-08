# Pharma BI Agents - Ballerina HTTP service
FROM ballerina/ballerina:2201.12.9

WORKDIR /app

# Copy the entire Ballerina project
COPY . .

# Optional: remove existing Dependencies.toml and let bal build regenerate it
RUN rm -f Dependencies.toml && bal build

# Expose agent HTTP port
EXPOSE 8293

# Run the compiled artifact to avoid recompiling inside the container
CMD ["bal", "run", "target/bin/pharma_agent.jar"]
