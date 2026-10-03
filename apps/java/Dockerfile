FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY App.java ./
RUN javac -d /app App.java

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app ./
EXPOSE 8080
ENTRYPOINT ["java", "-cp", "/app", "App"]
