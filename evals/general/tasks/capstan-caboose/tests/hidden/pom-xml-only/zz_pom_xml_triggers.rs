#[test]
    fn pom_xml_alone_still_triggers_maven_module() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        File::create(dir.path().join("pom.xml"))?.sync_all()?;

        let actual = ModuleRenderer::new("maven").path(dir.path()).collect();

        let expected = Some(format!(
            "via {}",
            Color::LightCyan.bold().paint("🅼 ")
        ));
        assert_eq!(expected, actual);
        dir.close()
    }