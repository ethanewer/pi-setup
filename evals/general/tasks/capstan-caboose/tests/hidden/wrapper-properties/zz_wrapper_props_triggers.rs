#[test]
    fn wrapper_properties_alone_triggers_maven_module() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        let properties = dir
            .path()
            .join(".mvn")
            .join("wrapper")
            .join("maven-wrapper.properties");
        fs::create_dir_all(properties.parent().unwrap())?;
        let mut file = File::create(properties)?;
        file.write_all(
            b"\
wrapperVersion=3.3.4
distributionType=only-script
distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.7/apache-maven-3.9.7-bin.zip
extraKey=ignored
",
        )?;
        file.sync_all()?;

        let actual = ModuleRenderer::new("maven").path(dir.path()).collect();

        let expected = Some(format!(
            "via {}",
            Color::LightCyan.bold().paint("🅼 v3.9.7 ")
        ));
        assert_eq!(expected, actual);
        dir.close()
    }