#[test]
    fn mvn_dir_without_pom_or_wrapper_does_not_trigger_module() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        let mvn = dir.path().join(".mvn");
        fs::create_dir_all(&mvn)?;
        File::create(mvn.join("settings.xml"))?.sync_all()?;

        let actual = ModuleRenderer::new("maven").path(dir.path()).collect();

        let expected = None;
        assert_eq!(expected, actual);
        dir.close()
    }