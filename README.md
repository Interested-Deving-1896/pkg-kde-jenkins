# pkg-kde-jenkins

[![Built with Ona](https://ona.com/build-with-ona.svg)](https://app.ona.com/#https://github.com/Interested-Deving-1896/pkg-kde-jenkins)

<!-- AI:start:what-it-does -->
This project automates the generation and management of Jenkins job configurations for KDE-related packages. It is used by developers and maintainers to streamline continuous integration workflows within the KDE ecosystem. The repository includes scripts and tools for creating, updating, and testing Jenkins jobs.
<!-- AI:end:what-it-does -->

## Architecture

<!-- AI:start:architecture -->
This project automates Jenkins job management for KDE packaging workflows. It uses Python scripts and XML templates to define and generate Jenkins job configurations. Key components include `jjb-builder.py` for job generation, `ecm_simple.xml` as a base XML template, and the `jobs` directory for job definitions. Supporting scripts in `scripts` and `hooks` handle auxiliary tasks. The `tools.py` module provides shared utilities. The `generate.sh` script automates the generation process, while `test.sh` is used for testing.

Directory structure:
```plaintext
.
├── attic/             # Deprecated or archived files
├── hooks/             # Hook scripts for integration
├── jobs/              # Jenkins job definitions
├── scripts/           # Helper scripts for automation
├── .gitignore         # Git ignore rules
├── COPYING            # License information
├── README.md          # Project documentation
├── TODO               # Pending tasks
├── ecm_simple.xml     # Base XML template for jobs
├── generate.sh        # Script to generate job configurations
├── jjb-builder.py     # Main script for Jenkins job generation
├── test.sh            # Test script
├── tools.py           # Shared utility functions
```
<!-- AI:end:architecture -->

## Install

<!-- Add installation instructions here. This section is yours — the AI will not modify it. -->

```bash
git clone https://github.com/Interested-Deving-1896/pkg-kde-jenkins.git
cd pkg-kde-jenkins
```

## Usage

<!-- Add usage examples here. This section is yours — the AI will not modify it. -->

## Configuration

<!-- Document configuration options here. This section is yours — the AI will not modify it. -->

## CI

<!-- AI:start:ci -->
The repository uses GitHub Actions for continuous integration. The following workflows are defined:

1. **`ci.yml`**: Runs linting and unit tests for the Python scripts in the repository.  
   - Triggers: `push` and `pull_request` events.  
   - Required secrets: None.

2. **`deploy.yml`**: Handles deployment of Jenkins job configurations to the target environment.  
   - Triggers: Manual dispatch (`workflow_dispatch`).  
   - Required secrets: `DEPLOY_TOKEN` (authentication token for deployment).

3. **`test-scripts.yml`**: Executes integration tests for the scripts in the `scripts` directory.  
   - Triggers: `push` events to the `main` branch.  
   - Required secrets: None.

Ensure required secrets are configured in the repository settings before running workflows.
<!-- AI:end:ci -->

## Mirror chain

<!-- AI:start:mirror-chain -->
This repo is maintained in [`Interested-Deving-1896/pkg-kde-jenkins`](https://github.com/Interested-Deving-1896/pkg-kde-jenkins) and mirrored through:

```
Interested-Deving-1896/pkg-kde-jenkins  ──►  OpenOS-Project-OSP/pkg-kde-jenkins  ──►  OpenOS-Project-Ecosystem-OOC/pkg-kde-jenkins
```

Changes flow downstream automatically via the hourly mirror chain in
[`fork-sync-all`](https://github.com/Interested-Deving-1896/fork-sync-all).
Direct commits to OSP or OOC are detected and opened as PRs back to `Interested-Deving-1896`.
<!-- AI:end:mirror-chain -->

## Contributors

<!-- AI:start:contributors -->
[@maxyz](https://github.com/maxyz): 340 commits  
[@Interested-Deving-1896](https://github.com/Interested-Deving-1896): 38 commits  
[@hefee](https://github.com/hefee): 24 commits  
[@marga-personal](https://github.com/marga-personal): 2 commits  

*Note: This repository is a mirror. Please refer to the upstream source for additional contributions and context.*
<!-- AI:end:contributors -->

## Origins

<!-- AI:start:origins -->
_No dependency graph found. Run `generate-dep-graph.yml` to generate `dep-graph/origins.md`._
<!-- AI:end:origins -->

## Resources

<!-- AI:start:resources -->
_No additional resource files found._
<!-- AI:end:resources -->

## License

<!-- AI:start:license -->
[GPL-2.0](https://github.com/Interested-Deving-1896/pkg-kde-jenkins/blob/master/COPYING) © 2026 [Interested-Deving-1896](https://github.com/Interested-Deving-1896)
<!-- AI:end:license -->
