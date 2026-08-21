PYTHON ?= python3
BINARY := .build/release/PetDock
APP    := build/PetDock.app
IDENT  := io.github.bluesmilery.codexpetdock

.PHONY: build app run diagnose clean clean-logs docs-check test-docs test test-ui test-data test-shell test-privacy

build:
	swift build -c release

app: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BINARY) $(APP)/Contents/MacOS/PetDock
	@cp build-resources/Info.plist $(APP)/Contents/Info.plist
	@cp build-resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
	@codesign -s - --force --identifier $(IDENT) $(APP)
	@echo "已构建: $(APP)"

run: app
	@open $(APP)
	@echo "已启动。日志: $(HOME)/Library/Application Support/PetDock/Logs/petdock.log（停止: pkill -f PetDock）"

diagnose: app
	@open $(APP) --args --diagnose
	@sleep 1
	@test -f "$(HOME)/Library/Application Support/PetDock/Diagnostics/diagnose.txt" && echo "已生成 Application Support/PetDock/Diagnostics/diagnose.txt" \
		|| echo "未生成输出（多半是屏幕录制权限未授予：CGPreflightScreenCaptureAccess()==false）"

clean:
	swift package clean
	rm -rf build

clean-logs:
	rm -f "$(HOME)/Library/Application Support/PetDock/Logs/petdock.log" \
		"$(HOME)/Library/Application Support/PetDock/Logs/petdock.log.1" \
		"$(HOME)/Library/Application Support/PetDock/Diagnostics/diagnose.txt"

# UI 测试：selectPet 识别 + Geometry 坐标 + Follower 状态机（纯函数，需 Cocoa）。
test-ui:
	swiftc -warnings-as-errors -DPETDOCK_TESTING tests/main.swift Sources/PetDock/PetTracker.swift Sources/PetDock/Geometry.swift Sources/PetDock/Follower.swift Sources/PetDock/FollowTickPlan.swift Sources/PetDock/DockModel.swift Sources/PetDock/Theme.swift Sources/PetDock/DockView.swift Sources/PetDock/DockPanel.swift Sources/PetDock/DetailPanel.swift Sources/PetDock/BubbleVisibility.swift Sources/PetDock/RuntimeEvidence.swift Sources/PetDock/PrivateStorage.swift Sources/PetDock/PetLogger.swift -framework Cocoa -framework ScreenCaptureKit -o /tmp/petdock-uitests
	/tmp/petdock-uitests

# 数据层测试（独立入口 + fixture，不依赖屏幕录制权限 / 不联网）。
# 注意：tests/DataTests.swift 用 @main，须作为编译入口与 Sources/PetDock/Data/*.swift + DockModel.swift
# （LiveDockProvider 映射测试依赖 DockSnapshot）一同编译。
test-data:
	swiftc Sources/PetDock/PrivateStorage.swift Sources/PetDock/Data/*.swift Sources/PetDock/DockModel.swift tests/DataTests.swift -o /tmp/petdock-datatests
	/tmp/petdock-datatests

# Shell 测试：Theme/Settings/ThemeStore/AutoStart 纯函数 + fixture（需 Cocoa + ServiceManagement）。
test-shell:
	swiftc tests/shell/main.swift Sources/PetDock/Theme.swift Sources/PetDock/Settings.swift Sources/PetDock/AutoStart.swift Sources/PetDock/StatusBar.swift -framework Cocoa -framework ServiceManagement -o /tmp/petdock-shelltests
	/tmp/petdock-shelltests

docs-check:
	$(PYTHON) tools/check_docs.py .

test-docs:
	$(PYTHON) tests/test_check_docs.py

test-privacy:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m pytest -q tests/test_runtime_privacy.py

# 全量测试：文档门禁 + privacy + UI + 数据(含 LiveDockProvider 映射) + Shell。
test: docs-check test-docs test-privacy test-ui test-data test-shell
	@echo "全部测试通过（Swift 断言 + privacy/docs gate）"
