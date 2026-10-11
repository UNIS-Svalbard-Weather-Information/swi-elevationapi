# Upstream image last built 2021-07-30 on Ubuntu 20.04 (end of support): see the security
# note in README.md. Pinned by digest so the base cannot change underneath a build.
FROM openelevation/open-elevation:latest@sha256:82fb21612e86ba847c1f30b6c9a2f457a26a929841a5754282ee2c9fea018639

# Set the working directory
WORKDIR /code

# Copy the run script to the container
COPY run.sh /code/prep-and-run-server.sh

# Make the script executable
RUN chmod +x /code/prep-and-run-server.sh

# Expose the necessary ports
EXPOSE 8080
EXPOSE 8443

# Command to run the script when the container starts
CMD ["/code/prep-and-run-server.sh"]
