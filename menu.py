import subprocess
import sys

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

# === 显示菜单并获取用户选择 ===
def get_mode_and_directions():
    print("\n请选择操作：")
    print("1. 沙雕模式（自动根据余额选择跨链方向）")
    print("2. 普通模式（手动选择跨链方向）")
    print("3. 查看日志")
    print("4. 暂停运行")
    print("5. 删除脚本")
    print("6. 请作者喝杯瑞幸咖啡（自动转账 10 ETH）")
    choice = input("输入选项（1-6）: ").strip()
    
    if choice not in ["1", "2", "3", "4", "5", "6"]:
        print("无效选项，请输入 1-6")
        return None, None
    
    selected_directions = []
    if choice == "2":
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

# === 检查 pm2 进程状态 ===
def check_pm2_process():
    result = subprocess.run(["pm2", "pid", "cross-chain"], capture_output=True, text=True)
    return result.returncode == 0 and int(result.stdout.strip()) > 0

# === 停止 pm2 进程 ===
def stop_pm2_process():
    subprocess.run(["pm2", "stop", "cross-chain"])

# === 查看 pm2 日志 ===
def view_pm2_logs():
    subprocess.run(["pm2", "logs", "cross-chain", "--lines", "15"])

# === 启动 worker.py ===
def start_worker(mode, directions=""):
    stop_pm2_process()  # 先停止现有进程
    cmd = ["pm2", "start", "worker.py", "--name", "cross-chain", "--interpreter", "python3"]
    if mode == "1":
        cmd.extend(["--", "silly"])
    elif mode == "2":
        cmd.extend(["--", "normal", directions])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        subprocess.run(["pm2", "save"])
        print("跨链脚本已通过 pm2 启动，进程名称为 cross-chain")
        print("你可以使用以下命令管理脚本：")
        print("  查看状态：pm2 status")
        print("  查看日志：pm2 logs cross-chain")
        print("  停止脚本：pm2 stop cross-chain")
        print("  重启脚本：pm2 restart cross-chain")
    else:
        print("pm2 启动脚本失败，请检查 pm2 状态")

# === 主函数 ===
def main():
    display_banner()
    
    # 收集用户输入并保存
    config = load_config()
    if not config:
        private_keys_input, chat_id = get_user_input()
        save_config(private_keys_input, chat_id)
    else:
        private_keys_input, chat_id = config["PRIVATE_KEYS"], config["CHAT_ID"]
    
    # 菜单循环
    while True:
        choice, directions = get_mode_and_directions()
        if choice in ["1", "2"]:
            save_config(private_keys_input, chat_id, f"{choice}:{directions}")
            start_worker(choice, directions)
            print("按 Enter 返回菜单...")
            input()
        elif choice == "3":
            if check_pm2_process():
                view_pm2_logs()
            else:
                print("cross-chain 进程未运行，无法查看日志")
            print("按 Enter 返回菜单...")
            input()
        elif choice == "4":
            if check_pm2_process():
                subprocess.run(["pm2", "stop", "cross-chain"])
                print("脚本已暂停")
            else:
                print("cross-chain 进程未运行")
            print("按 Enter 继续运行或返回菜单...")
            input()
            if check_pm2_process():
                subprocess.run(["pm2", "restart", "cross-chain"])
            else:
                print("请重新选择模式以启动脚本")
        elif choice == "5":
            print("正在删除脚本...")
            if check_pm2_process():
                subprocess.run(["pm2", "delete", "cross-chain"])
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
        elif choice == "6":
            print("正在处理转账，请稍候...")
            continue

if __name__ == "__main__":
    main()
