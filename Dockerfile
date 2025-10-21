FROM tomcat:9-jdk17-openjdk
COPY . /usr/local/tomcat/webapps/ROOT/
EXPOSE 8080
CMD ["catalina.sh", "run"]
