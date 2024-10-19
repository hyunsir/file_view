#!/bin/bash

# 初始化界面，显示当前目录和提示信息
function init_ui {
    tput clear  # 清屏
    echo "当前目录：$(pwd)"
    echo "使用上下键选择，右箭头进入文件夹，左箭头返回上一层，按 q 退出。"
    # 动态生成分隔符，长度与窗口宽度一致
    local total_width=$(tput cols)
    printf '=%.0s' $(eval "echo {1..$total_width}")
    echo ""
}

# 将字节数转为人类可读格式（KB、MB等）
function human_readable_size {
    size=$1
    if command -v numfmt > /dev/null; then
        # 使用 numfmt 转换，并在数字和单位之间添加空格
        numfmt --to=iec --suffix=" B" --format="%.1f" "$size"
    else
        # 手动转换为可读格式，添加空格
        if [ "$size" -lt 1024 ]; then
            echo "${size} B"
        elif [ "$size" -lt 1048576 ]; then
            echo "$((size / 1024)) KB"
        elif [ "$size" -lt 1073741824 ]; then
            echo "$((size / 1048576)) MB"
        else
            echo "$((size / 1073741824)) GB"
        fi
    fi
}

# 列出当前目录下的所有文件和文件夹，并手动分类
function list_items {
    items=()
    items_details=()

    # 先获取目录
    for file in $(ls -1a); do
        if [ -d "$file" ]; then
            items+=("$file")
            items_details+=("")  # 目录不需要显示大小
        fi
    done

    # 再获取文件
    for file in $(ls -1a); do
        if [ ! -d "$file" ]; then
            items+=("$file")
            # 获取文件大小
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
            if [ -n "$size" ]; then
                # 转换为可读格式，带空格
                human_readable_size=$(human_readable_size "$size")
                items_details+=("$human_readable_size")
            else
                items_details+=("")  # 如果无法获取大小，显示为空
            fi
        fi
    done
}

# 获取当前终端窗口的大小
function get_terminal_size {
    rows=$(tput lines)  # 获取终端的行数
    cols=$(tput cols)  # 获取终端的列数
    display_lines=$((rows - 5))  # 计算可显示的行数，保留顶部提示区域
    left_width=$((cols / 2))  # 左侧的宽度为终端的一半
    right_width=$((cols - left_width - 2))  # 右侧宽度减去分隔符
}

# 显示文件和文件夹列表，并根据可显示区域滚动
function display_items {
    local current=$1
    local offset=$2
    local total=${#items[@]}
    
    # 文件名宽度，确保对齐
    local name_width=$((left_width - 12))  # 保留部分空位显示文件大小
    local size_width=10
    
    for ((i = 0; i < display_lines && (i + offset) < total; i++)); do
        file="${items[$((i + offset))]}"
        file_detail="${items_details[$((i + offset))]}"
        
        if [ -d "$file" ]; then
            # 文件夹显示为蓝色
            if [ $((i + offset)) -eq $current ]; then
                printf "\e[1;34m> %-*s\e[0m\n" "$name_width" "$file/"  # 高亮选中的文件夹，左对齐
            else
                printf "  \e[1;34m%-*s\e[0m\n" "$name_width" "$file/"  # 普通文件夹，左对齐
            fi
        elif [ -x "$file" ]; then
            # 可执行文件显示为绿色
            if [ $((i + offset)) -eq $current ]; then
                printf "\e[1;32m> %-*s %*s\e[0m\n" "$name_width" "$file" "$size_width" ""  # 高亮选中的可执行文件，左对齐，右侧空白
            else
                printf "  \e[1;32m%-*s %*s\e[0m\n" "$name_width" "$file" "$size_width" ""  # 普通可执行文件，左对齐，右侧空白
            fi
        else
            # 普通文件显示大小
            if [ $((i + offset)) -eq $current ]; then
                printf "> %-*s %*s\n" "$name_width" "$file" "$size_width" "$file_detail"  # 高亮选中的普通文件，左对齐，右侧显示大小
            else
                printf "  %-*s %*s\n" "$name_width" "$file" "$size_width" "$file_detail"  # 普通文件，左对齐，右侧显示大小
            fi
        fi
    done
}

# 显示所选文件的前几行内容
function display_file_preview {
    local file=$1
    local max_lines_to_display=$((rows - 7))  # 可显示的最大行数，根据当前终端大小
    local lines_to_display=$((max_lines_to_display))

    if [ -f "$file" ]; then
        # 使用 head 命令读取前几行，并通过 perl 检测二进制字符
        if head -n "$lines_to_display" "$file" | perl -ne 'if (/[\x00-\x08\x0B\x0C\x0E-\x1F]/) { exit 1 }'; then
            # 将光标移到右侧显示区域
            tput cup 2 $((left_width + 2))
            printf "\e[1;37m%-*s\e[0m\n" "$right_width" "文件预览：$file"

            # 动态生成分隔符，长度与右侧显示区域一致
            tput cup 3 $((left_width + 2))
            printf "%0.s-" $(seq 1 $right_width)
            echo ""

            # 使用 head 命令直接获取文件的前几行
            head -n "$lines_to_display" "$file" | while IFS= read -r line; do
                # 如果超过了右侧宽度，进行截断并添加"..."符号
                if [ "${#line}" -gt "$right_width" ]; then
                    line="${line:0:right_width-3}..."  # 截断行并添加"..."符号
                fi
                # 移动光标到右侧显示区域
                tput cup $((4 + count)) $((left_width + 2))
                printf "%-${right_width}s\n" "$line"
                ((count++))
            done

            # 动态生成结束分隔符
            tput cup $((3 + lines_to_display + 1)) $((left_width + 2))
            printf "%0.s-" $(seq 1 $right_width)
            echo ""
        else
            # 二进制文件显示简短提示
            tput cup 2 $((left_width + 2))
            printf "\e[1;37m%-*s\e[0m\n" "$right_width" "文件预览：$file (二进制文件，不支持预览)"
        fi
    fi
}

# 主循环
function main {
    local current_selection=0   # 当前选择的文件或文件夹的索引
    local scroll_offset=0  # 控制滚动偏移量
    list_items
    get_terminal_size
    init_ui

    while true; do
        get_terminal_size  # 每次循环都重新获取窗口大小
        # 刷新屏幕并重新显示内容
        tput clear
        init_ui

        # 显示左侧的文件列表
        display_items $current_selection $scroll_offset  # 显示文件和文件夹列表
        # 显示右侧的文件预览（如果是文件）
        display_file_preview "${items[$current_selection]}"

        # 等待用户按键
        read -rsn1 key
        case "$key" in
            $'\x1b')  # 处理箭头按键
                read -rsn2 key
                case "$key" in
                    "[A")  # 上箭头
                        ((current_selection--))
                        if [ $current_selection -lt 0 ]; then
                            current_selection=$((${#items[@]} - 1))  # 跳转到最后一个文件
                            scroll_offset=$((${#items[@]} - display_lines))  # 滚动到最底部
                            if [ $scroll_offset -lt 0 ]; then
                                scroll_offset=0  # 防止文件数量少于 display_lines 的情况
                            fi
                        elif [ $current_selection -lt $scroll_offset ]; then
                            ((scroll_offset--))  # 滚动向上
                        fi
                        ;;
                    "[B")  # 下箭头
                        ((current_selection++))
                        if [ $current_selection -ge ${#items[@]} ]; then
                            current_selection=0  # 跳转到第一个文件
                            scroll_offset=0  # 滚动到最顶部
                        elif [ $current_selection -ge $((scroll_offset + display_lines)) ]; then
                            ((scroll_offset++))  # 滚动向下
                        fi
                        ;;
                    "[C")  # 右箭头：如果光标在文件夹上，进入文件夹
                        if [ -d "${items[$current_selection]}" ]; then
                            cd "${items[$current_selection]}"
                            list_items
                            current_selection=0
                            scroll_offset=0
                            init_ui
                        fi
                        ;;
                    "[D")  # 左箭头：返回上一层文件夹
                        cd ..
                        list_items
                        current_selection=0
                        scroll_offset=0
                        init_ui
                        ;;
                esac
                ;;
            "")  # 回车键：如果是目录，进入该目录；如果是文件，预览文件
                if [ -d "${items[$current_selection]}" ]; then
                    cd "${items[$current_selection]}"
                    list_items  # 刷新文件列表
                    current_selection=0
                    scroll_offset=0  # 重置滚动偏移
                    get_terminal_size  # 重新获取窗口大小
                    init_ui
                elif [ -f "${items[$current_selection]}" ]; then
                    # 如果是文件，显示预览
                    display_file_preview "${items[$current_selection]}"
                fi
                ;;
            q)  # 按 'q' 退出并进入当前浏览的目录
                cd "$(pwd)"
                tput clear
                exit 0
                ;;
        esac
    done
}

# 运行主程序
main
