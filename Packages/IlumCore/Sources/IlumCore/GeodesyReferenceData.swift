import Foundation

extension GeodesyReferenceCatalog {
    public static let entries: [GeodesyReferenceEntry] = [
        entry(
            "erhe", "Erhebungserlass NRW (ErhE)", kind: "Verwaltungsvorschrift",
            section: "Nr. 1–2; Teile zum Raumbezug und Liegenschaftskataster; Anlagen",
            summary: "Der ErhE beschreibt Qualität, Umfang, Messverfahren und nachvollziehbare Dokumentation amtlicher Geobasisdaten. Messungen sind an den einheitlichen Raumbezug anzuschließen und durchgreifend zu kontrollieren. Für freie Stationierung, Genauigkeitsmaße und Vermessungsschriften sind die einschlägigen Anlagen heranzuziehen. Die Stammfassung nennt ältere Realisierungen des Raumbezugs; zusätzlich die Einführung der Realisierung 2025 prüfen.",
            caution: "Verlinkt ist die Stammnorm, keine nachgewiesen vollständige aktuelle Konsolidierung. Eine Änderung vom 10.12.2019 ist separat verlinkt; weitere Änderungen und Anlagen vor Anwendung prüfen. Keine Toleranzwerte aus dieser Kurzfassung ableiten.",
            edition: "Stammnorm 15.09.2017; gesonderte Änderung 10.12.2019",
            url: "https://recht.nrw.de/lrmb/verwaltungsvorschrift/erhebung-der-geobasisdaten-des-amtlichen-vermessungswesens-nordrhein/",
            related: ["https://recht.nrw.de/mblnrw/2019-s790/"],
            aliases: ["erhe", "erhebungserlass", "vermessung", "freie stationierung", "genauigkeit", "геодезія", "знімання", "точність", "вільна станція"]
        ),
        entry(
            "vermkatg", "VermKatG NRW — Kataster und Zuständigkeiten", kind: "Landesgesetz",
            section: "Vermessungs- und Katastergesetz NRW",
            summary: "Gesetzlicher Ausgangspunkt für Landesvermessung und Liegenschaftskataster in NRW: Aufgaben, zuständige Vermessungsstellen, Geobasisdaten, Raumbezug und Liegenschaftsvermessungen. Vor einem Auftrag unterscheiden, ob technische Ingenieurvermessung oder eine amtliche Katasterleistung benötigt wird.",
            caution: "Zuständigkeit und konkrete Verfahrenspflicht am vollständigen Gesetz prüfen. NRW-Regeln gelten nicht automatisch in anderen Ländern.",
            edition: "Portal-Fassung 08.12.2020",
            url: "https://recht.nrw.de/lrgv/gesetz/08122020-gesetz-ueber-die-landesvermessung-und-das-liegenschaftskataster-vermessungs/",
            aliases: ["vermkatg", "kataster", "zuständigkeit", "кадастр", "геодезія", "повноваження"]
        ),
        entry(
            "dvo-vermkatg", "DVOzVermKatG NRW — Durchführung", kind: "Landesverordnung",
            section: "Durchführungsverordnung zum VermKatG NRW",
            summary: "Ergänzt das VermKatG mit Durchführungsvorgaben für Landesvermessung und Kataster. Für konkrete Leistungen zusammen mit Gesetz, einschlägigem Erlass und Vorgaben der zuständigen Katasterbehörde lesen. Datenmodell, Verfahrensanforderungen und Zuständigkeit getrennt prüfen.",
            caution: "Die Verordnung ist kein Ersatz für das VermKatG oder dessen aktuelle Änderungen.",
            edition: "Portal-Fassung 19.02.2022",
            url: "https://recht.nrw.de/lrgv/rechtsverordnung/19022022-verordnung-zur-durchfuehrung-des-gesetzes-ueber-die-landesvermessung/",
            aliases: ["dvozvermkatg", "durchführung", "кадастр", "порядок"]
        ),
        entry(
            "kataster-fuehrung", "LiegKatErl — Führung des Liegenschaftskatasters", kind: "Verwaltungsvorschrift",
            section: "Liegenschaftskatastererlass NRW",
            summary: "Thematischer Einstieg in Führung und Fortführung des Liegenschaftskatasters. Erhebung von Vermessungsdaten und Übernahme in den amtlichen Nachweis sind unterschiedliche Arbeitsschritte. Für die Übergabe die aktuellen fachlichen und technischen Vorgaben der Katasterbehörde ermitteln.",
            caution: "Historische Stammnorm: nicht als bestätigten aktuellen ALKIS-Abgabestandard verwenden. Änderungen und aktuelle Anwendungsschemata gesondert prüfen.",
            edition: "Stammnorm 13.01.2009; Änderungsstand nicht konsolidiert geprüft",
            url: "https://recht.nrw.de/lrmb/verwaltungsvorschrift/die-fuehrung-des-liegenschaftskatasters-nordrhein-westfalen/",
            aliases: ["liegkaterl", "fortführung", "katasterführung", "кадастр", "оновлення кадастру"]
        ),
        entry(
            "grz", "GRZ — Grundflächenzahl", jurisdiction: "DE", kind: "Bundesverordnung",
            section: "§ 19 BauNVO, insbesondere Abs. 3–5",
            summary: "Die GRZ beschreibt die zulässige Grundfläche je maßgeblicher Grundstücksfläche. Der Nenner ist nach Abs. 3 zu bestimmen, nicht pauschal aus jeder Flurstücksfläche. Garagen, Stellplätze samt Zufahrten, Nebenanlagen und bestimmte unterirdische Anlagen werden nach Abs. 4 mitgerechnet. Im Regelfall ist hierfür eine Überschreitung um 50 % bis höchstens GRZ 0,8 vorgesehen; Planfestsetzungen und Ausnahmen können abweichen. Rechenbeispiel unter diesen Annahmen: 600 m² × 0,4 = 240 m²; einschließlich dieser Anlagen insgesamt 360 m², nicht zusätzlich 360 m².",
            caution: "Bebauungsplan und anzuwendende BauNVO-Fassung prüfen. Abs. 5 enthält Sonderregeln für Solar- und Windenergie in bestimmten Gebieten. Die Beispielrechnung bestätigt keine Baugenehmigung.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz",
            edition: "Online-Einzelnorm beim Abruf; für Altpläne kann eine andere BauNVO-Fassung gelten",
            url: "https://www.gesetze-im-internet.de/baunvo/__19.html",
            aliases: ["grz", "grundflächenzahl", "grundflaechenzahl", "грз", "коефіцієнт забудови", "площа забудови", "versiegelung"]
        ),
        entry(
            "gfz", "GFZ — Geschossflächenzahl", jurisdiction: "DE", kind: "Bundesverordnung",
            section: "§ 20 BauNVO",
            summary: "Die GFZ bezieht die Geschossfläche auf die maßgebliche Grundstücksfläche. Die Geschossfläche wird grundsätzlich nach den Außenmaßen der Gebäude in den Vollgeschossen bestimmt. Was als Vollgeschoss gilt, richtet sich nach Landesrecht; der Bebauungsplan kann zusätzliche Festsetzungen zur Anrechnung enthalten. Geschossfläche, Wohnfläche und GRZ sind unterschiedliche Größen.",
            caution: "Landesrechtliche Vollgeschossdefinition und planbezogene BauNVO-Fassung vor der Berechnung feststellen.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf",
            url: "https://www.gesetze-im-internet.de/baunvo/__20.html",
            aliases: ["gfz", "geschossflächenzahl", "geschossflaechenzahl", "vollgeschoss", "гфз", "поверховість", "площа поверхів"]
        ),
        entry(
            "baugrenze", "Baugrenze, Baulinie und Baufenster", jurisdiction: "DE", kind: "Bundesverordnung",
            section: "§ 23 BauNVO",
            summary: "Eine Baulinie legt grundsätzlich fest, auf welcher Linie gebaut werden muss; eine Baugrenze begrenzt grundsätzlich den Bereich, den Gebäude nicht überschreiten dürfen. Ausnahmen und Planfestsetzungen sind gesondert zu lesen. Überbaubare Fläche, zulässige Grundfläche und Abstandsflächen müssen jeweils geprüft werden.",
            caution: "Eine eingehaltene GRZ erlaubt nicht automatisch das Überschreiten einer Baugrenze.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf",
            url: "https://www.gesetze-im-internet.de/baunvo/__23.html",
            aliases: ["baugrenze", "baulinie", "baufenster", "межа забудови", "лінія забудови"]
        ),
        entry(
            "bebauungsplan", "Bebauungsplan — planungsrechtliche Grundlage", jurisdiction: "DE + Gemeinde", kind: "Bundesgesetz / örtlicher Plan",
            section: "§ 30 BauGB",
            summary: "Bei einem qualifizierten Bebauungsplan richtet sich die Zulässigkeit nach dessen Festsetzungen und der gesicherten Erschließung. Bei einem einfachen Plan sind ergänzend § 34 oder § 35 relevant. Für eine Projektprüfung Gemeinde, Planbezeichnung, rechtsverbindliche Zeichnung, textliche Festsetzungen, Änderungen und maßgebliche BauNVO-Fassung beschaffen.",
            caution: "Der Katalog enthält keine kommunalen Bebauungspläne. Keinen konkreten Bauanspruch aus einer GRZ allein ableiten.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf; örtlicher Plan projektbezogen erforderlich",
            url: "https://www.gesetze-im-internet.de/bbaug/__30.html",
            aliases: ["bebauungsplan", "bplan", "b plan", "erschließung", "генплан", "план забудови", "містобудування"]
        ),
        entry(
            "aussenbereich", "Außenbereich — Zulässigkeit von Vorhaben", jurisdiction: "DE", kind: "Bundesgesetz",
            section: "§ 35 BauGB",
            summary: "Im Außenbereich gelten besondere Voraussetzungen. Privilegierte und sonstige Vorhaben werden unterschiedlich behandelt; Erschließung und öffentliche Belange sind zu prüfen. Eine vermessene Grundstücksgröße und rechnerische GRZ reichen für die Zulässigkeitsbeurteilung nicht aus.",
            caution: "Zuerst klären, ob ein Vorhaben tatsächlich dem Außenbereich zuzuordnen ist; lokale Planung und Behördenentscheidung einbeziehen.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf",
            url: "https://www.gesetze-im-internet.de/bbaug/__35.html",
            aliases: ["außenbereich", "aussenbereich", "privilegiert", "поза населеним пунктом"]
        ),
        entry(
            "teilung", "Grundstücksteilung und Flurstück", jurisdiction: "DE", kind: "Bundesgesetz",
            section: "§ 19 BauGB; ergänzend Landesrecht",
            summary: "Die Teilung im Sinne des BauGB betrifft die grundbuchliche Verselbständigung eines Grundstücksteils. Grundstück und katastertechnisches Flurstück sind nicht gleichzusetzen. Im Geltungsbereich eines Bebauungsplans dürfen durch Teilung keine planwidrigen Verhältnisse entstehen. Für NRW zusätzlich § 7 BauO NRW und die einschlägigen Bauvorlagen prüfen.",
            caution: "Eine katastertechnische Zerlegung allein ersetzt weder Grundbuchvollzug noch erforderliche bauordnungsrechtliche Prüfung.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf",
            url: "https://www.gesetze-im-internet.de/bbaug/__19.html",
            aliases: ["teilung", "zerlegung", "flurstück", "flurstueck", "поділ", "ділянка", "земельна ділянка"]
        ),
        entry(
            "abstandsflaechen", "Abstandsflächen in NRW", kind: "Landesgesetz",
            section: "§ 6 BauO NRW 2018",
            summary: "Die Abstandsflächenprüfung hängt unter anderem von Wandhöhe, Gelände, Dachgeometrie, Gebiet und gesetzlichen Ausnahmen ab. Für die Vermessung werden belastbare Grenzen, Höhen und Gebäudemaße benötigt. Abstandsflächen und planungsrechtliches Baufenster sind getrennte Prüfungen.",
            caution: "Keine allgemeine Pauschalregel von drei Metern für jedes Gebäude ansetzen. Vollständigen § 6 und örtliche Regelungen prüfen.",
            edition: "Portal-Fassung gültig ab 01.09.2026",
            url: "https://recht.nrw.de/lrgv/gesetz/01092026-landesbauordnung-2018-bauo-nrw-2018/",
            aliases: ["abstandsflächen", "abstandsflaechen", "grenzabstand", "відступ", "відстань до межі"]
        ),
        entry(
            "baulasten", "Baulasten und Baulastenverzeichnis NRW", kind: "Landesgesetz",
            section: "§ 85 BauO NRW 2018",
            summary: "Baulasten sind öffentlich-rechtliche Verpflichtungen zu einem Grundstück. Sie werden im Baulastenverzeichnis geführt. Für Lageplan und Grundstücksprüfung den einschlägigen Nachweis bei der zuständigen Bauaufsichtsbehörde einbeziehen; Grundbuch und Baulastenverzeichnis haben unterschiedliche Funktionen.",
            caution: "Eine Baulast ist nicht mit einer privatrechtlichen Grunddienstbarkeit gleichzusetzen. Ein unauffälliger Grundbuchauszug ersetzt die Baulastenauskunft nicht.",
            edition: "Portal-Fassung gültig ab 01.09.2026",
            url: "https://recht.nrw.de/lrgv/gesetz/01092026-landesbauordnung-2018-bauo-nrw-2018/",
            aliases: ["baulast", "baulasten", "baulastenverzeichnis", "обтяження", "сервітут"]
        ),
        entry(
            "lageplan", "Lageplan und Bauvorlagen in NRW", kind: "Landesverordnung",
            section: "§ 3 BauPrüfVO; §§ 17–18 für Teilung und Baulast",
            summary: "Die BauPrüfVO regelt Inhalte der Bauvorlagen. § 3 ist der zentrale Einstieg für den Lageplan; weitere Vorschriften betreffen Unterlagen für Teilung und Baulast. Grenzen, vorhandene und geplante Bebauung, Höhen und planungsrechtliche Angaben müssen dem jeweiligen Verfahren entsprechend aufbereitet werden.",
            caution: "Ein beliebiger Kartenausdruck ersetzt keinen verfahrensgerechten Lageplan. Anforderungen an Erstellung und amtliche Ausfertigung anhand des konkreten Falls prüfen.",
            edition: "Portal-Fassung 26.11.2024",
            url: "https://recht.nrw.de/lrgv/rechtsverordnung/26112024-verordnung-ueber-bautechnische-pruefungen-baupruefvo-1/",
            aliases: ["lageplan", "amtlicher lageplan", "bauprüfvo", "baupruefvo", "bauvorlagen", "ситуаційний план", "топоплан"]
        ),
        entry(
            "gebaeudeeinmessung", "Gebäudeeinmessungspflicht NRW", kind: "Landesgesetz",
            section: "§ 16 VermKatG NRW",
            summary: "Bei Errichtung oder Veränderung des Grundrisses eines Gebäudes ist die katasterrechtliche Einmessungspflicht zu prüfen. Die gesetzliche Pflicht und ihre Durchführung sind von Bauabsteckung, Baukontrolle und Bestandsaufnahme für private Planungszwecke zu unterscheiden.",
            caution: "Konkrete Voraussetzungen, Pflichtige und Verfahren aus Gesetz und Durchführungsregeln feststellen; keine pauschale Frist aus dieser Kurzfassung ableiten.",
            edition: "Portal-Fassung 08.12.2020",
            url: "https://recht.nrw.de/lrgv/gesetz/08122020-gesetz-ueber-die-landesvermessung-und-das-liegenschaftskataster-vermessungs/",
            aliases: ["gebäudeeinmessung", "gebaeudeeinmessung", "einmessungspflicht", "обмір будівлі", "знімання будівель"]
        ),
        entry(
            "grenzzeichen", "Grenzabmarkung und Grenzzeichen", jurisdiction: "DE + Landesrecht", kind: "Bundesgesetz",
            section: "§ 919 BGB",
            summary: "§ 919 behandelt die Mitwirkung benachbarter Eigentümer bei der Errichtung oder Wiederherstellung fester Grenzzeichen. Art und Verfahren richten sich vorrangig nach Landesrecht. Für NRW die katasterrechtlichen Regeln und den amtlichen Grenznachweis hinzuziehen.",
            caution: "Die Norm ist keine Erlaubnis, Grenzzeichen eigenmächtig zu versetzen. Kartendarstellung, Zaunlage und rechtliche Grenze können voneinander abweichen.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf",
            url: "https://www.gesetze-im-internet.de/bgb/__919.html",
            aliases: ["grenzabmarkung", "grenzzeichen", "grenzstein", "grenze", "межа", "межі", "межовий знак"]
        ),
        entry(
            "grundbuch", "Grundbucheinsicht", jurisdiction: "DE", kind: "Bundesgesetz",
            section: "§ 12 GBO",
            summary: "Grundbucheinsicht setzt nach § 12 grundsätzlich ein dargelegtes berechtigtes Interesse voraus. Für eine Grundstücksprüfung unterscheiden: Grundbuch für den grundbuchlichen Rechtsnachweis, Liegenschaftskataster für den katasterlichen Nachweis und das gesonderte Baulastenverzeichnis.",
            caution: "Der Katalog vermittelt keinen Zugriff auf geschützte Eigentümerdaten. Einsichtsberechtigung im konkreten Verfahren klären.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Einzelnorm beim Abruf",
            url: "https://www.gesetze-im-internet.de/gbo/__12.html",
            aliases: ["grundbuch", "gbo", "eigentümer", "земельна книга", "власник"]
        ),
        entry(
            "gebuehren", "Vermessungsgebühren NRW", kind: "Landesverordnung",
            section: "VermWertKostO NRW und Kostentarif",
            summary: "Die Vermessungs- und Wertermittlungskostenordnung samt Kostentarif ist der Einstieg für öffentlich-rechtliche Gebühren und Auslagen entsprechender Leistungen in NRW. Vor einer Schätzung die konkrete Leistung, Tarifstelle, Bemessungsgrundlage und zum maßgeblichen Zeitpunkt geltende Fassung bestimmen.",
            caution: "Keine pauschalen Euro-Beträge aus diesem Katalog. Amtliche Gebühren und frei vereinbarte technische Leistungen nicht vermischen.",
            edition: "Portal-Fassung 01.01.2026",
            url: "https://recht.nrw.de/lrgv/rechtsverordnung/01012026-vermessungs-und-wertermittlungskostenordnung-vermwertkosto-nrw/",
            aliases: ["vermwertkosto", "gebühren", "gebuehren", "kosten", "тарифи", "вартість", "збори"]
        ),
        entry(
            "oebvi", "ÖbVI — öffentlich bestellte Vermessungsingenieure", kind: "Landesgesetz",
            section: "ÖbVIG NRW",
            summary: "Das Berufsrecht der öffentlich bestellten Vermessungsingenieurinnen und Vermessungsingenieure in NRW regelt Stellung und Berufsausübung. Bei amtlichen Leistungen zuerst klären, welche Stelle die Leistung rechtlich ausführen darf; technische Fachkenntnis allein begründet keine hoheitliche Befugnis.",
            caution: "Berufsrecht ist landesspezifisch. Bestellung und konkreten Befugnisumfang prüfen.",
            edition: "Portal-Fassung 18.11.2023",
            url: "https://recht.nrw.de/lrgv/gesetz/18112023-gesetz-ueber-die-oeffentlich-bestellten-vermessungsingenieurinnen-und/",
            aliases: ["öbvi", "oebvi", "öbvig", "berufsrecht", "геодезист", "присяжний геодезист"]
        ),
        entry(
            "raumbezug", "Raumbezug NRW — Realisierung 2025", kind: "Amtliche Fachinformation",
            section: "Geobasis NRW: Raumbezug",
            summary: "NRW führte am 01.07.2025 eine neue Realisierung des geodätischen Raumbezugs ein. Bei Austausch und Vergleich von Messungen Lage- und Höhenbezug, Realisierung und zeitlichen Bezug dokumentieren. Ein Systemname allein beschreibt nicht sämtliche für einen präzisen Vergleich relevanten Eigenschaften.",
            caution: "Ältere Vorschriften können noch Realisierung 2016 nennen. Aktuelle Einführungshinweise und Projektdaten prüfen; Koordinaten nicht ungeprüft zusammenführen.",
            publisher: "Bezirksregierung Köln / Geobasis NRW", edition: "Fachseite beim Abruf; Einführung 01.07.2025",
            url: "https://www.bezreg-koeln.nrw.de/geobasis-nrw/produkte-und-dienste/raumbezug",
            aliases: ["raumbezug", "etrs89", "utm", "dhhn2016", "nhn", "höhen", "координати", "система координат", "висоти"]
        ),
        entry(
            "sapos", "SAPOS HEPS — GNSS in Echtzeit", kind: "Amtliche Dienstinformation",
            section: "SAPOS HEPS NRW",
            summary: "SAPOS HEPS stellt Korrekturdaten für hochpräzise GNSS-Echtzeitpositionierung bereit. Die Betreiberseite beschreibt Formate, Zugang und Dienstmerkmale. Für die praktische Arbeit Empfängerprofil, Antennenbezug, Korrekturdienst und Qualitätskontrolle zusammen betrachten.",
            caution: "Eine Hersteller- oder Dienstgenauigkeit garantiert nicht die Qualität jedes einzelnen Messpunkts. Abschattung, Mehrwegeeffekte und Kontrollmessungen im konkreten Auftrag berücksichtigen.",
            publisher: "Bezirksregierung Köln / Geobasis NRW", edition: "Dienstbeschreibung beim Abruf",
            url: "https://www.bezreg-koeln.nrw.de/geobasis-nrw/produkte-und-dienste/raumbezug/satellitenpositionierungsdienst-sapos/sapos-heps",
            aliases: ["sapos", "heps", "gnss", "rtk", "ntrip", "gps", "супутникова зйомка", "поправки"]
        ),
        entry(
            "transformation", "Koordinatentransformation NRW", kind: "Amtliche Fachinformation",
            section: "Geobasis NRW: Transformation und Stützpunktdatei",
            summary: "Die amtliche Fachseite erschließt Transformationsangebote und Stützpunkte für NRW. Vor einer Umrechnung Quell- und Zielsystem, Realisierung, Einheiten und Genauigkeitsziel festlegen. Bei Katasterdaten die Eignung einer katasterkonformen Transformation prüfen.",
            caution: "Das Umbenennen eines Koordinatensystems transformiert keine Koordinaten. Restklaffen und unabhängige Kontrollpunkte bei der fachlichen Bewertung berücksichtigen.",
            publisher: "Bezirksregierung Köln / Geobasis NRW", edition: "Fachseite beim Abruf",
            url: "https://www.bezreg-koeln.nrw.de/geobasis-nrw/produkte-und-dienste/raumbezug/transformation",
            aliases: ["transformation", "stützpunkte", "gauss krüger", "gauß", "epsg", "трансформація", "перетворення координат"]
        ),
        entry(
            "kalibrierung", "Prüfung von Tachymetern und GNSS-Rovern", kind: "Amtliche Fachinformation",
            section: "Geobasis NRW: Systemprüfung; Bezug zum ErhE",
            summary: "Für im amtlichen Vermessungswesen eingesetzte Tachymeter und GNSS-Rover beschreibt Geobasis NRW jährliche und anlassbezogene Prüfungen. Geräteprüfung, Kalibrierung und Justierung sind verschiedene Vorgänge. Prüfnachweise und verwendete Gerätekonfiguration gehören zur nachvollziehbaren Qualitätssicherung.",
            caution: "Anlass, Frist und Prüfverfahren anhand der aktuellen amtlichen Vorgaben prüfen; eine Werkskalibrierung ersetzt nicht automatisch jeden vorgeschriebenen Nachweis.",
            publisher: "Bezirksregierung Köln / Geobasis NRW", edition: "Fachseite beim Abruf",
            url: "https://www.bezreg-koeln.nrw.de/geobasis-nrw/produkte-und-dienste/raumbezug/pruefung-und-kalibrierung/tachymeter-und-gnss-rover",
            aliases: ["kalibrierung", "prüfung", "tachymeter", "justierung", "калібрування", "тахеометр", "перевірка приладів"]
        ),
        entry(
            "alkis", "ALKIS, AFIS, ATKIS und GeoInfoDok", jurisdiction: "DE / Länderprofile", kind: "Amtliches Datenmodell",
            section: "AdV GeoInfoDok — aktuelle Anwendungsschemata",
            summary: "GeoInfoDok beschreibt die AAA-Anwendungsschemata für AFIS, ALKIS und ATKIS. Für Schnittstellen und NAS-Daten Datenmodellversion, Schema, Objektartenkatalog und das jeweilige Länderprofil zusammen prüfen. Ein syntaktisch gültiger Datensatz belegt für sich keine vermessungstechnische Genauigkeit.",
            caution: "Gesamtkonzept, Anwendungsschema und Landesprofil können unterschiedliche Versionsstände haben. Abgabeformat mit der empfangenden Stelle abstimmen.",
            publisher: "Arbeitsgemeinschaft der Vermessungsverwaltungen der Länder (AdV)", edition: "Anwendungsschema-Übersicht beim Abruf; Version je Teilprodukt prüfen",
            url: "https://www.adv-online.de/en/geoinfodok/aktuelle-anwendungsschemata",
            aliases: ["alkis", "afis", "atkis", "nas", "geoinfodok", "aaa", "gml", "кадастрові дані", "схема даних"]
        ),
        entry(
            "planzeichen", "Planzeichen und Planlegende", jurisdiction: "DE", kind: "Bundesverordnung",
            section: "Planzeichenverordnung (PlanZV) und Anlage",
            summary: "Die PlanZV ist die Grundlage für Planzeichen in Bauleitplänen. Beim Lesen eines Bebauungsplans Zeichnung, Legende und textliche Festsetzungen gemeinsam auswerten. Die zugehörige amtliche Anlage dient als Referenz für standardisierte Zeichen.",
            caution: "Ein isoliertes Symbol oder eine Bildschirmfarbe reicht nicht für eine belastbare Planauslegung; Originalplan und Legende prüfen.",
            publisher: "Bundesministerium der Justiz / Bundesamt für Justiz", edition: "Online-Verordnung beim Abruf",
            url: "https://www.gesetze-im-internet.de/planzv_90/",
            aliases: ["planzv", "planzeichen", "legende", "умовні знаки", "легенда"]
        ),
        entry(
            "tim-online", "TIM-online — amtliche Karten NRW", kind: "Amtlicher Kartendienst",
            section: "Geobasis NRW: TIM-online",
            summary: "TIM-online ist ein Einstieg zur Ansicht amtlicher Geobasisdaten in NRW. Für die Arbeitsvorbereitung die ausgewählten Ebenen, deren Herkunft, Maßstab und Aktualität festhalten und bei Bedarf geeignete amtliche Auszüge beschaffen.",
            caution: "Ein Bildschirmabgriff ersetzt keine Grenzfeststellung und keinen vorgeschriebenen amtlichen Lageplan. Nutzungsbedingungen der jeweiligen Daten beachten.",
            publisher: "Bezirksregierung Köln / Geobasis NRW", edition: "Dienstseite beim Abruf",
            url: "https://www.bezreg-koeln.nrw.de/geobasis-nrw/tim-online",
            aliases: ["tim online", "karten", "orthofoto", "геопортал", "карта", "ортофото"]
        ),
        entry(
            "boris", "BORIS-NRW — Grundstücksmarkt", kind: "Amtlicher Informationsdienst",
            section: "BORIS-NRW",
            summary: "BORIS-NRW ist das zentrale Informationssystem der Gutachterausschüsse und des Oberen Gutachterausschusses für Grundstückswerte in NRW. Es dient als Einstieg in amtliche Informationen zum Grundstücksmarkt.",
            caution: "Bei jeder Wertinformation Stichtag, Bezugsobjekt und Erläuterungen prüfen. Eine Marktinformation ersetzt keine objektspezifische Wertermittlung.",
            publisher: "Gutachterausschüsse / Oberer Gutachterausschuss NRW", edition: "Portal beim Abruf; Stichtag je Datensatz",
            url: "https://www.boris.nrw.de/boris-nrw/",
            aliases: ["boris", "bodenrichtwert", "wertermittlung", "оцінка землі", "вартість землі"]
        ),
        entry(
            "din-18710", "DIN 18710 — Ingenieurgeodäsie", jurisdiction: "DE", kind: "Technische Norm (Metadaten)",
            section: "DIN 18710-1:2025-08; Normenreihe",
            summary: "DIN 18710-1:2025-08 behandelt allgemeine Anforderungen der Ingenieurgeodäsie. Die Ausgabe 2010-09 wurde ersetzt. Die Normenreihe ist ein fachlicher Einstieg für Planung, Ausführung, Auswertung und Dokumentation von Ingenieurvermessungen.",
            caution: "Hier sind nur bibliografische Hinweise enthalten, keine lizenzierten Normtexte oder Toleranztabellen. Anwendbare Ausgabe und vertragliche Vorgaben anhand rechtmäßig zugänglicher Originalunterlagen prüfen.",
            publisher: "DIN / DIN Media", edition: "DIN 18710-1:2025-08; Verlagsmetadaten",
            url: "https://www.dinmedia.de/en/standard/din-18710-1/391193955",
            aliases: ["din", "18710", "ingenieurvermessung", "ingenieurgeodäsie", "absteckung", "monitoring", "інженерна геодезія", "розбивка", "деформації"]
        ),
        entry(
            "drohnen", "Drohnenvermessung — DIPUL", jurisdiction: "DE + EU / örtliche Gebiete", kind: "Amtliches Informationsportal",
            section: "Digitale Plattform Unbemannte Luftfahrt",
            summary: "DIPUL bündelt Informationen zur unbemannten Luftfahrt und führt zum Kartendienst für geografische UAS-Gebiete. Vor photogrammetrischer Befliegung am konkreten Ort und Datum Betriebsbedingungen, Gebietsbeschränkungen und erforderliche Berechtigungen ermitteln.",
            caution: "Eine geplante Vermessung befreit nicht automatisch von Luftverkehrsregeln. Der Katalog enthält keine Freigabe für einen konkreten Flug und keine vollständige Luftrechtsprüfung.",
            publisher: "Bundesministerium für Verkehr / DIPUL", edition: "Informationsangebot beim Abruf; Flugdatum gesondert prüfen",
            url: "https://www.bmv.de/DE/Themen/Mobilitaet/Luft/Digitale-Plattform-Unbemannte-Luftfahrt/digitale-plattform-unbemannte-luftfahrt.html",
            related: ["https://www.dipul.de/homepage/de/", "https://maptool-dipul.dfs.de/?language=de"],
            aliases: ["drohne", "drohnen", "uas", "dipul", "photogrammetrie", "дрон", "фотограмметрія", "аерозйомка"]
        )
    ]

    private static func entry(
        _ id: String, _ title: String,
        jurisdiction: String = "DE-NW", kind: String, section: String,
        summary: String, caution: String,
        publisher: String = "Land Nordrhein-Westfalen / RECHT.NRW.DE",
        edition: String, url: String, related: [String] = [], aliases: [String]
    ) -> GeodesyReferenceEntry {
        GeodesyReferenceEntry(
            id: id, title: title, jurisdiction: jurisdiction, kind: kind, section: section,
            summary: summary, caution: caution, publisher: publisher, sourceEdition: edition,
            reviewedOn: snapshotDate, sourceURL: url, relatedSourceURLs: related, aliases: aliases
        )
    }
}
