# Runtime tool resources

External executables are not stored in this package. Release packaging owns the
final App `Contents/Resources/Tools` directory and may copy only versions declared
in the repository-level
`Tools/tool-lock.json`, after the checksum-verifying fetch and package scripts
validate their provenance, architecture, dependencies, licenses, and signatures.
The App adapter injects that directory URL; PodPin production code never searches
`Bundle.main` or environment variables for executable paths.
