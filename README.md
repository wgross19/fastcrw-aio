# Unraid AIO App Template

Starter repository for creating one Unraid AIO application package in the Unraid App Factory.

This template provides:

- A Dockerfile wrapper pattern.
- `s6-overlay` runtime supervision.
- An Unraid Community Applications XML template.
- Root filesystem initialization and service examples.
- Integration test scaffolding.
- Public-repository documentation and support files.
- The `.aio-fleet.yml` contract used by the central App Factory.

## Create an app

1. Create a new repository from this template.
2. Replace the placeholder Dockerfile and runtime commands.
3. Rename and customize `template-aio.xml`.
4. Replace the icon and application documentation.
5. Replace the starter tests with real lifecycle checks.
6. Register the repository in `aio-fleet/fleet.yml`.
7. Export the generated `.aio-fleet.yml` contract.
8. Run central validation before publishing an image.

Keep application-specific runtime behavior in the app repository. Keep shared validation, release, registry, upstream, and catalog behavior in the App Factory.
