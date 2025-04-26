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

def display_banner():
    banner = """
    ╔════════════════════════════════════════════════════════════════════╗
    ║                                                                    ║
    ║   🚀 由 @hao3313076 一天一夜没睡匠心制作！🚀                           ║
    ║   💥 不关注我的推特 @hao3313076，JJ短10cm！💥                         ║
    ║   📢 需要消息推送关注@t3rntz_bot！📢                                  ║
    ║                                                                    ║
    ╚════════════════════════════════════════════════════════════════════╝
    """
    print(banner)

def save_config(private_keys_input, chat_id):
    with open("config.txt", "w") as f:
        f.write(f"PRIVATE_KEYS={private_keys_input}\n")
        f.write(f"CHAT_ID={chat_id}\n")

def main():
    display_banner()
    private_keys_input, chat_id = get_user_input()
    save_config(private_keys_input, chat_id)
    print("配置已保存到 config.txt")

if __name__ == "__main__":
    main()
