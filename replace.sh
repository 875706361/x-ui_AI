#!/bin/bash

# 读取原始文件内容
original_content=$(cat web/service/inbound.go)

# 定义要搜索和替换的内容
search_str="for _, traffic := range traffics {\nif traffic.IsInbound {\nerr = tx.Where(\"tag = ?\", traffic.Tag).\\nUpdateColumn(\"up\", gorm.Expr(\"up + ?\", traffic.Up)).\\nUpdateColumn(\"down\", gorm.Expr(\"down + ?\", traffic.Down)).\\nError\nif err != nil {\nreturn\n}\n}\n}"

replace_str="// 批量处理，减少数据库操作次数\nbatchSize := 50\nfor i := 0; i < len(traffics); i += batchSize {\nend := i + batchSize\nif end > len(traffics) {\nend = len(traffics)\n}\n\nbatch := traffics[i:end]\nfor _, traffic := range batch {\nif traffic.IsInbound {\nerr = tx.Where(\"tag = ?\", traffic.Tag).\\nUpdateColumn(\"up\", gorm.Expr(\"up + ?\", traffic.Up)).\\nUpdateColumn(\"down\", gorm.Expr(\"down + ?\", traffic.Down)).\\nError\nif err != nil {\nreturn\n}\n}\n}\n}"

# 执行替换
new_content="${original_content//$search_str/$replace_str}"

# 写回文件
echo "$new_content" > web/service/inbound.go

