import subprocess
import sys
import os
import platform

# === 清屏函数 ===
def clear_screen():
    os.system("cls" if platform.system() == "Windows" else "clear")

# === 收集用户输入并保存到 config.txt ===
def get_user_input():
    print("\n请输入私钥（多个用+分隔）:")
    private_keys_input = input().strip()
    if not private_keys_input:
        print("私钥不能为空")
        exit(1)
    
    print("请输入 Telegram 聊天 ID:")
    chat_id = input().strip()
    if not chat_id:
        print("Telegram 聊天 ID 不能为空")
        exit(1)
    
    return private_keys_input, chat_id

def save_config(private_keys_input, chat_id, mode=""):
    with open("config.txt", "w") as f:
        f.write(f"PRIVATE_KEYS={private_keys_input}\n")
        f.write(f"CHAT_ID={chat_id}\n")
        f.write(f"MODE={mode}\n")

def load_config():
    try:
        with open("config.txt", "r") as f:
            config = {}
            for line in f:
                key, value = line.strip().split("=", 1)
                config[key] = value
        return config
    except FileNotFoundError:
        return None

# === 显示横幅 ===
def display_banner():
    banner = """
    ╔════════════════════════════════════════════════════════════════════╗
    ║                                                                    ║
    ║   🚀 由 @hao3313076 一天一夜没睡匠心制作！🚀                           ║
    ║   💥 不关注我的推特 @hao3313076，JJ短10cm！💥                         ║
    ║   📢 快去 Twitter 关注我，获取最新跨链动态和福利！📢                     ║
    ║                                                                    ║
    ╚════════════════════════════════════════════════════════════════════╝
    """
    print(banner)

# === 隐藏私钥显示 ===
def mask_private_key(key):
    if len(key) < 12:
        return key
    return f"{key[:6]}****{key[-6:]}"

# === 账户管理 ===
def manage_accounts(private_keys_input, chat_id):
    private_keys = private_keys_input.split("+")
    while True:
        clear_screen()
        display_banner()
        print("\n账户管理：")
        print("1. 添加私钥")
        print("2. 删除私钥")
        print("3. 查看私钥列表")
        print("4. 返回主菜单")
        choice = input("输入选项（1-4）: ").strip()
        
        if choice == "1":
            new_key = input("请输入新私钥: ").strip()
            if new_key:
                private_keys.append(new_key)
                private_keys_input = "+".join(private_keys)
                save_config(private_keys_input, chat_id)
                print("私钥已添加")
            else:
                print("私钥不能为空")
        elif choice == "2":
            if not private_keys:
                print("当前没有私钥")
            else:
                print("\n当前私钥列表：")
                for idx, key in enumerate(private_keys, 1):
                    print(f"{idx}. {mask_private_key(key)}")
                try:
                    idx = int(input("请输入要删除的私钥编号: ")) - 1
                    if 0 <= idx < len(private_keys):
                        deleted_key = private_keys.pop(idx)
                        private_keys_input = "+".join(private_keys) if private_keys else ""
                        save_config(private_keys_input, chat_id)
                        print(f"私钥 {mask_private_key(deleted_key)} 已删除")
                    else:
                        print("无效的编号")
                except ValueError:
                    print("请输入有效的数字")
        elif choice == "3":
            if not private_keys:
                print("当前没有私钥")
            else:
                print("\n当前私钥列表：")
                for idx, key in enumerate(private_keys, 1):
                    print(f"{idx}. {mask_private_key(key)}")
        elif choice == "4":
            break
        else:
            print("无效选项，请输入 1-4")
        print("按 Enter 继续...")
        input()

# === 显示菜单并获取用户选择 ===
def get_mode_and_directions():
    clear_screen()
    display_banner()
    print("\n请选择操作：")
    print("1. 账户管理")
    print("2. 沙雕模式（自动根据余额选择跨链方向）")
    print("3. 普通模式（手动选择跨链方向）")
    print("4. 查看日志")
    print("5. 暂停运行")
    print("6. 删除脚本")
    print("7. 请作者喝杯瑞幸咖啡（自动转账 10 ETH）")
    choice = input("输入选项（1-7）: ").strip()
    
    if choice not in ["1", "2", "3", "4", "5", "6", "7"]:
        print("无效选项，请输入 1-7")
        return None, None
    
    selected_directions = []
    if choice == "3":
        print("\n可用跨链方向：")
        for idx, desc in enumerate([
            "UNI -> ARB", "UNI -> OP", "UNI -> Base",
            "ARB -> UNI", "ARB -> OP", "ARB -> Base",
            "OP -> UNI", "OP -> ARB", "OP -> Base",
            "Base -> UNI", "Base -> ARB", "Base -> OP"
        ], 1):
            print(f"{idx}. {desc}")
        choices = input("请输入跨链方向编号（逗号分隔，例如 1,2,5）: ").strip()
        if not choices:
            print("未选择任何跨链方向")
            return None, None
        try:
            selected_indices = [int(x) - 1 for x in choices.split(",")]
            selected_directions = [str(i + 1) for i in selected_indices if 0 <= i < 12]
            if not selected_directions:
                print("无效的跨链方向选择")
                return None, None
        except ValueError:
            print("跨链方向编号必须为数字")
            return None, None
    
    return choice, ",".join(selected_directions) if selected_directions else ""

# === 启动 worker.py ===
def start_worker(mode, directions=""):
    # 使用 screen 启动 worker.py
    if mode == "2":
        cmd = f"screen -dmS cross_chain python3 worker.py silly"
    elif mode == "3":
        cmd = f"screen -dmS cross_chain python3 worker.py normal {directions}"
    subprocess.run(cmd, shell=True)
    print("跨链脚本已在 screen 会话（cross_chain）中启动")
    print("你可以使用以下命令管理脚本：")
    print("  查看 screen 会话：screen -ls")
    print("  进入 screen 会话：screen -r cross_chain")
    print("  查看日志：cat worker.log")

# === 查看日志 ===
def view_logs():
    print("\n=== 最近 15 行日志 ===")
    try:
        with open("worker.log", "r") as f:
            lines = f.readlines()[-15:]
        for line in lines:
            print(line.strip())
    except FileNotFoundError:
        print("未找到 worker.log 文件，脚本可能未运行")

# === 暂停运行 ===
def stop_worker():
    subprocess.run("screen -S cross_chain -X quit", shell=True)
    print("脚本已暂停")

# === 主函数 ===
def main():
    # 收集用户输入并保存
    config = load_config()
    if not config:
        display_banner()
        private_keys_input, chat_id = get_user_input()
        save_config(private_keys_input, chat_id)
    else:
        private_keys_input, chat_id = config["PRIVATE_KEYS"], config["CHAT_ID"]
    
    # 菜单循环
    while True:
        choice, directions = get_mode_and_directions()
        if choice == "1":
            manage_accounts(private_keys_input, chat_id)
            config = load_config()
            private_keys_input, chat_id = config["PRIVATE_KEYS"], config["CHAT_ID"]
        elif choice in ["2", "3"]:
            save_config(private_keys_input, chat_id, f"{choice}:{directions}")
            start_worker(choice, directions)
            print("按 Enter 返回菜单...")
            input()
        elif choice == "4":
            view_logs()
            print("按 Enter 返回菜单...")
            input()
        elif choice == "5":
            stop_worker()
            print("按 Enter 继续运行或返回菜单...")
            input()
        elif choice == "6":
            print("正在删除脚本...")
            stop_worker()
            try:
                os.remove(__file__)
                os.remove("worker.py")
                os.remove("config.txt")
                print("脚本已删除，程序退出")
                sys.exit(0)
            except Exception as e:
                print(f"删除脚本失败: {e}")
                print("请手动删除文件")
                sys.exit(1)
        elif choice == "7":
            print("正在处理转账，请稍候...")
            continue
        clear_screen()

if __name__ == "__main__":
    main()
