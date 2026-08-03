BINARY := .build/release/PetDock
APP    := build/PetDock.app
IDENT  := io.github.bluesmilery.codexpetdock

.PHONY: build app run diagnose clean clean-logs test-data

build:
	swift build -c release

app: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BINARY) $(APP)/Contents/MacOS/PetDock
	@cp build-resources/Info.plist $(APP)/Contents/Info.plist
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
	@codesign -s - --force --identifier $(IDENT) $(APP)
	@echo "已构建: $(APP)"

run: app
	@rm -f /tmp/petdock.log
	@open $(APP)
	@echo "已启动。日志: /tmp/petdock.log（停止: pkill -f PetDock）"

diagnose: app
	@rm -f /tmp/petdock-diagnose.txt
	@open $(APP) --args --diagnose
	@sleep 1
	@test -f /tmp/petdock-diagnose.txt && echo "已生成 /tmp/petdock-diagnose.txt" \
		|| echo "未生成输出（多半是屏幕录制权限未授予：CGPreflightScreenCaptureAccess()==false）"

clean:
	swift package clean
	rm -rf build

clean-logs:
	rm -f /tmp/petdock.log /tmp/petdock-diagnose.txt

# 数据层测试（独立入口 + fixture，不依赖屏幕录制权限 / 不联网）。
# 注意：tests/DataTests.swift 用 @main，须作为编译入口与 Sources/PetDock/Data/*.swift 一同编译。
test-data:
	swiftc Sources/PetDock/Data/*.swift tests/DataTests.swift -o /tmp/petdock-datatests
	/tmp/petdock-datatests
