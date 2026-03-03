# Twingate Linux Connector (Docker Image)

This image provides a lightweight, self-contained way to run the **Twingate Linux/systemd Connector in a Docker container**. In most cases it is preferable to run the official Twingate container image, but in some situations there may be a need for custom scripts, healthchecks, or being able to leverage a shell within the container. This custom image is an example of how that can be achieved in a fairly straight-forward way.

For more information on the Twingate Connector in a Linux environment, see the [Twingate Linux Connector documentation](https://www.twingate.com/docs/connectors-on-linux).

**Note**: If you are not familiar with third party container registries such as GHCR (GitHub Container Registry), please see the [GHCR Authentication Guide](#ghcr-github-container-registry-authentication-guide) at the bottom of this README.

---

## Usage

### 1. Provision a new Twingate Connector

In the Twingate Admin Console, go to **Network** → **Remote Networks** → choose the Remote Network → **+ Add Connector**. Click the new Connector and choose the **Manual** deployment option.

Scroll down to **Step 2** and click **Generate Tokens**. This will produce an **Access Token** and a **Refresh Token**. Copy these values for use in the next step (adding them to the `docker-compose.yml`).

### 2. Example `docker-compose.yml`

This is an example `docker-compose.yml` file to get you started. Replace the placeholder values with your own. The three required environment variables are:

- `TWINGATE_NETWORK`: Your Twingate network name (e.g. from the Admin Console subdomain `mycompany.twingate.com` just the `mycompany` part)
- `TWINGATE_ACCESS_TOKEN`: The Access Token generated in Step 1
- `TWINGATE_REFRESH_TOKEN`: The Refresh Token generated in Step 1

There are two optional environment variables you can set as well:

- `TWINGATE_LOG_ANALYTICS`: Set to `v2` to enable detailed traffic logging
- `TWINGATE_LOG_LEVEL`: Set the log verbosity level (default is `3`; set to `7` for debug logging)

```yaml
services:
  tg-headless-connector:
    image: ghcr.io/twingate-solutions/twingate-custom-connector-container:latest  
    privileged: true

    environment:
      - TWINGATE_NETWORK=<YOUR_TWINGATE_NETWORK>
      - TWINGATE_ACCESS_TOKEN=<ACCESS_TOKEN>
      - TWINGATE_REFRESH_TOKEN=<REFRESH_TOKEN>
      #- TWINGATE_LOG_ANALYTICS=v2 #remove the comment tag on this if you want detailed traffic logging
      #- TWINGATE_LOG_LEVEL=3 #remove the comment tag and set this to 7 if you want debug logging enabled

    tty: true

    restart: unless-stopped

```

### 3. Start the connector

```bash
docker compose up -d
docker compose logs -f tg-headless-connector
```

### 4. Access the container

If you need to run tests or check the status of the Connector from within the container, you can get a shell like this:

```bash
docker compose exec -it tg-headless-connector bash
# Once inside the container, you can check the Connector status:
twingate-connectorctl health
```

It will show `OK` if the Connector is running and connected properly.

---

## Health Checks and Container Health

The container utilizes a `healthcheck` that will run any executable scripts placed in the `/healthchecks.d/` directory (run interval is 90s by default). Each script should return `0` for success or a non-zero exit code for failure; if any check fails the container will be marked unhealthy.

Example health checks included:

- `00-twingate-status-healthcheck.sh`: Checks that the Twingate Connector is running and connected.

Any additional checks can be added by placing executable scripts in `/healthchecks.d/` following the same success/failure and naming conventions.

---

## Forking and Customization

This repository hosts a small Connector container and helper scripts. If you fork it you can:

- Modify the `Dockerfile` to add additional tools or monitoring.
- Adjust `entrypoint.sh` to change startup or log-forwarding behavior.
- Add or change health checks in `/healthchecks.d/` to match your environment.

You can also publish your customized image to your own GHCR namespace (authentication steps below still apply) or private ACR/ECR type of container registry.

---

## GHCR (GitHub Container Registry) Authentication Guide

### Adding GHCR (GitHub Container Registry)

GHCR (hosted at `ghcr.io`) is GitHub's container registry. To use images stored on GHCR from Docker (pull or push), you need to authenticate Docker and reference images with the `ghcr.io/OWNER/IMAGE:TAG` name.

1) Create a Personal Access Token (PAT)

  - Go to GitHub and create a PAT with the appropriate scopes. For pulling only, `read:packages` is sufficient. To push images you will also need `write:packages` (and `repo` if you're working with private repositories). See [GitHub's PAT docs for details](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token).

2) Authenticate Docker to GHCR

   - Using an environment variable called `GITHUB_PAT` (recommended) you can log in without exposing the token in your shell history.

     - PowerShell (Windows):

       ```powershell
       echo $env:GITHUB_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
       ```

     - Bash (macOS / Linux):

       ```bash
       echo "$GITHUB_PAT" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
       ```

     - CMD (Windows cmd.exe):

       ```cmd
       echo %GITHUB_PAT% | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
       ```

- You can also run `docker login ghcr.io -u YOUR_GITHUB_USERNAME` and paste the PAT when prompted. Docker Desktop will store credentials in the OS credential store by default.

3) Pulling images from GHCR

   - Pull directly with Docker:

     ```bash
     docker pull ghcr.io/OWNER/IMAGE:TAG
     ```

   - Use the same image reference in `docker-compose.yml`:

     ```yaml
     services:
       myservice:
         image: ghcr.io/OWNER/IMAGE:TAG
     ```

4) Links and further reading

- About GHCR: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry/about-the-container-registry
- Authenticating to GHCR: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry/authenticating-to-github-container-registry
- Pushing & pulling: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry/pushing-and-pulling-containers

Notes:
- Use `read:packages` for pulls only; add `write:packages` (and `repo` for private repos) for pushes.
- When running on CI (GitHub Actions) prefer `GITHUB_TOKEN` or a repository/organization PAT with minimal scopes.

---