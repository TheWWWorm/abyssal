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
	expect(EngineLanguage.content_language("en",["DEEP","- 1 -","S.T.R.E.A.M."]).is_empty(),"Text with no telling words is an unknown language")
	expect(EngineLanguage.resolve(EngineLanguage.AUTO,"")==EngineLanguage.resolve(EngineLanguage.AUTO,OS.get_locale()),"An unknown game language falls back to the system language")
	expect(EngineLanguage.resolve(EngineLanguage.AUTO,"ru")=="ru","Auto follows the game")
	expect(EngineLanguage.resolve("de","ru")=="de","A chosen language wins over the game's")
	expect(EngineLanguage.resolve("xx","ru")=="ru","An unknown setting is Auto")
	expect(EngineLanguage.supported("pt_BR")=="pt" and EngineLanguage.supported("zh-Hans")=="zh" and EngineLanguage.supported("nl").is_empty(),"Regional locales find their language")
	var helm=load("res://native/presentation/classic_frame.gd").new();root.add_child(helm)
	var warning=load("res://native/presentation/hazard_warning.gd").new();root.add_child(warning)
	helm.throttle=100;helm.speed=16
	for code in EngineLanguage.codes():
		EngineLanguage.apply(code)
		expect(EngineLanguage.current==code and TranslationServer.get_locale()==code,"%s applies"%code)
		var resume := EngineLanguage.translate("Resume")
		expect((resume=="Resume")==(code=="en"),"%s translates engine text"%code)
		var thrust := EngineLanguage.translate("THRUST  %d%%")%100
		var speed := EngineLanguage.translate("TIME  %d×")%16
		var needed: float=helm.font.get_string_size(thrust,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x+helm.font.get_string_size(speed,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
		expect(helm.panel_rect().size.x-36>=needed+14,"%s helm leaves a gap between translated thrust and time"%code)
		check_warning_layout(warning,code)
		if EngineLanguage.FONTS.has(code):
			var font: Font=EngineLanguage.cjk_font(code)
			expect(font!=null,"%s has its bundled font"%code)
			if font!=null:
				for character in resume+EngineLanguage.native_name(code):
					if character.unicode_at(0)>=0x1100: expect(font.has_char(character.unicode_at(0)),"%s font draws %s"%[code,character])
			expect(ThemeDB.fallback_font.fallbacks.size()==EngineLanguage.FONTS.size(),"%s keeps every CJK font as a fallback"%code)
	EngineLanguage.apply("en")
	expect(EngineLanguage.translate("Resume")=="Resume","English is the source text")
	helm.queue_free();warning.queue_free()
	await check_live_language(content)
	print("ENGINE_LANGUAGE ",failures," failures")
	quit(1 if failures else 0)

func settle() -> void:
	for i in 6:await process_frame

func select_language(panel, code: String) -> void:
	var row=panel.find_option(panel,"language")
	expect(row!=null,"The display page has a language picker")
	if row==null:return
	var list: OptionButton=row.get_node("List")
	list.show_popup();await process_frame
	list.get_popup().index_pressed.emit(EngineLanguage.codes().find(code)+1)
	await settle()
	expect(EngineLanguage.current==code,"The open dropdown applies %s safely"%code)

func check_live_language(content) -> void:
	var title=load("res://scenes/native_main.tscn").instantiate()
	var config:=ConfigFile.new();config.set_value("interface","language","en")
	DirAccess.make_dir_recursive_absolute(title.settings_path.get_base_dir());config.save(title.settings_path)
	root.add_child(title);current_scene=title;await settle()
	for code in ["pt","ru","ja","en"]:
		title=current_scene;title.show_settings("display");await settle()
		await select_language(title.settings_panel,code)
		expect(is_instance_valid(current_scene.settings_panel) and current_scene.settings_panel.visible,"Title language changes reopen usable settings")
	current_scene.queue_free();current_scene=null;await process_frame
	var game=load("res://native/gameplay.gd").new();game.content=content
	game.save_path="user://language-test.json";game.settings_path="user://language-test.cfg"
	root.add_child(game);current_scene=game;game.set_process(false);game.close_page();await settle()
	for code in ["ru","pt","ko","en"]:
		game.show_settings("display");await settle()
		await select_language(game.settings_panel,code)
		expect(game.page=="settings" and game.settings_panel.visible,"In-game language changes keep settings open")
	game.queue_free();current_scene=null;await process_frame

func check_warning_layout(warning, code: String) -> void:
	for depth in [10000,30000]:
		for exposure in [0,2500,6000]:
			warning.status=warning.describe(depth,18400,25000,exposure)
			for width in [640,527,400]:
				warning.fit_width(width)
				var layout: Dictionary=warning.content_layout()
				var action_end: float=layout.right+warning.text_width(warning.status.action,27)
				expect(layout.arrow.x-7+0.01>=action_end+14,"%s depth arrow stays clear of the translated instruction"%code)
				expect(layout.arrow.x+7<=width-22,"%s depth arrow stays inside the warning"%code)
				expect(layout.right+warning.text_width(layout.safe,14)<=width-22,"%s safe depth fits the warning"%code)
				var title_end: float=88+maxf(warning.text_width(warning.status.title,19),warning.text_width(layout.damage,16))
				expect(title_end<=width-22 if layout.stacked else title_end<=layout.right-28,"%s warning columns do not overlap"%code)
				expect(22+warning.text_width(layout.exposure,11)+12<=layout.track_left,"%s exposure label stays clear of its bar"%code)
				expect(layout.track_left<width-22,"%s exposure bar has room"%code)
