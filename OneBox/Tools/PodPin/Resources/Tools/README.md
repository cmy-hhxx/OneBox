# Runtime tool resources

External executables are not stored in this source directory. Release packaging
may copy only the versions declared in the repository-level
`Tools/tool-lock.json`, after the checksum-verifying fetch and package scripts
validate their provenance, architecture, dependencies, licenses, and signatures.
