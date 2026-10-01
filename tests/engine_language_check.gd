extends SceneTree
## Engine text follows the imported game's language on Auto and a chosen one
## otherwise; every catalog loads, and the CJK languages draw with their
## bundled glyphs. Runs headless with the imported content as its argument.
const EngineLanguage = preload("res://native/presentation/engine_language.gd")
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok: failures+=1; push_error(why)
func _initialize(): call_deferred("run")
func run():
	var content=load("res://native/content.gd").new()
	expect(content.load_cache(OS.get_cmdline_user_args()[0]),"The imported content loads")
	var strings: Array=content.data.strings
	expect(EngineLanguage.content_language(str(content.data.get("language","")),strings)=="en","The English build reads as English")
	var russian := ["Начать новую игру","Загрузить игру","Настройки","Вы уверены, что хотите выйти?"]
	expect(EngineLanguage.content_language("ru",russian)=="ru","A ru folder reads as Russian")
	expect(EngineLanguage.content_language("en",russian)=="ru","Russian text under an en folder reads as Russian")
	expect(EngineLanguage.content_language("en",["Розпочати нову гру","Налаштування","Ви впевнені, що хочете вийти?","Їжа і є"])=="uk","Ukrainian letters read as Ukrainian")
	expect(EngineLanguage.content_language("en",["Neues Spiel starten","Die Station ist nicht mit dir verbunden und der Laderaum ist voll."])=="de","German text under an en folder reads as German")
	expect(EngineLanguage.content_language("en",["新しいゲームを始める","設定"])=="ja","Kana read as Japanese")
	expect(EngineLanguage.content_language("en",["开始新游戏","设置"])=="zh","Han without kana reads as Chinese")
	expect(EngineLanguage.content_language("en",["새 게임 시작","설정"])=="ko","Hangul reads as Korean")
	expect(EngineLanguage.resolve(EngineLanguage.AUTO,"ru")=="ru","Auto follows the game")
	expect(EngineLanguage.resolve("de","ru")=="de","A chosen language wins over the game's")
	expect(EngineLanguage.resolve("xx","ru")=="ru","An unknown setting is Auto")
	expect(EngineLanguage.supported("pt_BR")=="pt" and EngineLanguage.supported("zh-Hans")=="zh" and EngineLanguage.supported("nl").is_empty(),"Regional locales find their language")
	for code in EngineLanguage.codes():
		EngineLanguage.apply(code)
		expect(EngineLanguage.current==code and TranslationServer.get_locale()==code,"%s applies"%code)
		var resume := EngineLanguage.translate("Resume")
		expect((resume=="Resume")==(code=="en"),"%s translates engine text"%code)
		if EngineLanguage.FONTS.has(code):
			var font: Font=EngineLanguage.cjk_font(code)
			expect(font!=null,"%s has its bundled font"%code)
			if font!=null:
				for character in resume+EngineLanguage.native_name(code):
					if character.unicode_at(0)>=0x1100: expect(font.has_char(character.unicode_at(0)),"%s font draws %s"%[code,character])
			expect(ThemeDB.fallback_font.fallbacks.size()==EngineLanguage.FONTS.size(),"%s keeps every CJK font as a fallback"%code)
	EngineLanguage.apply("en")
	expect(EngineLanguage.translate("Resume")=="Resume","English is the source text")
	print("ENGINE_LANGUAGE ",failures," failures")
	quit(1 if failures else 0)
