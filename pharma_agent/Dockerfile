FROM ballerina/ballerina:2201.12.9
WORKDIR /app

USER root
COPY . .

# ensure the target directory can be cleaned/created
RUN rm -rf /app/target && bal build

EXPOSE 8293
CMD ["java", "-jar", "target/bin/pharma_agent.jar"]
