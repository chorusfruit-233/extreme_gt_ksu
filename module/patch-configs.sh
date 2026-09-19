#!/system/bin/sh
# Configuration transforms derived from upstream Extreme GT 4.2.1.
dirs=""
for dir in /odm /my_product /my_stock /my_heytap /vendor /product /system_ext /system; do
  [ -d "$dir" ] && dirs="$dirs $dir"
done

xml_override() {
  overrides="$2"

  find $dirs -type f -name "$1" 2>/dev/null | while IFS= read -r file; do
    mkdir -p "$(dirname "$module$file")"
    rows=$(cat "$file")
    for override in $overrides; do
      key=$(echo $override | cut -f1 -d '=')
      value=$(echo $override | cut -f2 -d '=')
      rows=$(echo "$rows" | sed "s|<$key>[^<]*</$key>|<$key>$value</$key>|g")
    done
    echo "$rows" > "$module$file"
  done
}

# sys_thermal_control_config.xml sys_thermal_control_config_gt.xml
boolValues="feature_enable_item feature_safety_test_enable_item aging_thermal_control_enable_item"
intValues="aging_cpu_level_item high_temp_safety_level_item game_high_perf_mode_item normal_mode_item ota_mode_item racing_mode_item"
find $dirs -type f -name "sys_thermal_control_config*.xml" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  rows=$(cat "$file" | grep -v -E '(<gear_config|cpu=|fps=|<scene_|</scene_|<category_|</category_|<subitem|<level|\.)')

  for key in $boolValues; do
    rows=$(echo "$rows" | sed "s/<$key.*\/>/<$key booleanVal=\"false\" \/>/")
  done

  for key in $intValues; do
    rows=$(echo "$rows" | sed "s/<$key.*\/>/<$key intVal=\"-1\" \/>/")
  done

  echo "$rows" | tr -s '\n' > "$module$file"
done

# sys_thermal_config.xml
xml_override 'sys_thermal_config.xml' "isOpen=0
more_heat_threshold=550
heat_threshold=530
less_heat_threshold=500
preheat_threshold=480
preheat_dex_oat_threshold=460
thermal_battery_temp=0
is_feature_on=0
is_upload_log=0
is_upload_errlog=0"

# sys_high_temp_protect_*。xml
xml_override 'sys_high_temp_protect*xml' "isOpen=0
HighTemperatureProtectSwitch=false
HighTemperatureShutdownSwitch=false
HighTemperatureFirstStepSwitch=false
HighTemperatureProtectFirstStepIn=550
HighTemperatureProtectFirstStepOut=530
HighTemperatureProtectThresholdIn=570
HighTemperatureProtectThresholdOut=550
HighTemperatureProtectShutDown=750
MediumTemperatureProtectThreshold=10000
HighTemperatureDisableFlashSwitch=false
HighTemperatureDisableFlashLimit=480
HighTemperatureEnableFlashLimit=470
HighTemperatureDisableFlashChargeSwitch=false
HighTemperatureDisableFlashChargeLimit=480
HighTemperatureEnableFlashChargeLimit=470
camera_temperature_limit=520
HighTemperatureControlVideoRecordSwitch=false
HighTemperatureDisableVideoRecordLimit=550
HighTemperatureEnableVideoRecordLimit=520
ToleranceThreshold=50
ToleranceStart=480
ToleranceStop=460"

patch_rr_config(){
  rr_config=$1
  # sed 's/<!--.*-->//' "$file" | grep -v -E '<item.*2-2-2-2.*/>' | sed 's/2-2-2-2/0-0-0-0/' | grep -v -E '<record' > "$module$file"
  sed -i 's/<!--.*-->//' "$rr_config"
  sed -i '/<item.*2-2-2-2.*\/>/d' "$rr_config"
  sed -i 's/2-2-2-2/0-0-0-0/' "$rr_config"
  sed -i '/<record/d' "$rr_config"
}

# refresh_rate_config.xml
find $dirs -type f -name "refresh_rate_config.xml" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  cp -fp "$file" "$module$file"
  patch_rr_config "$module$file"
done
# /data/system is not a systemless partition; do not edit its persistent cache.

# thermallevel_to_fps.xml
find $dirs -type f -name "thermallevel_to_fps.xml" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  cp -fp "$file" "$module$file"
  sed -i "s/fps=\"[^\"]*\"/fps=\"144\"/g" "$module$file"
done

# oppo_display_perf_list.xml
# multimedia_display_perf_list.xml
find $dirs -type f -name "oppo_display_perf_list.xml" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  echo -n '' > "$module$file"
  skip=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
     *"<name>"*)
       skip=0
       case "$line" in
        *"sf.dps.feature"*|*"com.android"*|*"system_server"*|*"/system"*|*"com.color"*|*"com.oppo"*|*"com.oplus"**"SmartVolume"*)
          skip=0
          echo "  $line" >> "$module$file"
        ;;
        *)
          skip=1
        ;;
       esac
     ;;
     '<?xml version="1.0" encoding="UTF-8"?>'|'<filter-conf>'|'</filter-conf>')
         echo "$line" >> "$module$file"
     ;;
     *)
       if [[ $skip == 0 ]]; then
         echo "  $line" >> "$module$file"
       fi
     ;;
    esac
  done < "$file"
done

# sys_resolution_switch_config.xml
find $dirs -type f -name "sys_resolution_switch_config.xml" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  echo -n '' > "$module$file"
  skip=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
     *"<item package="*|*"<switchop package="*)
       echo "$line" > /dev/null
     ;;
     *)
       echo "$line" >> "$module$file"
     ;;
    esac
  done < "$file"
done

# game_thermal_config.xml
find $dirs -type f -name "game_thermal_config.xml" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  echo -n '' > "$module$file"
  if [[ $(grep cluster3 "$file") != '' ]];then
  echo '<?xml version="1.0" encoding="utf-8"?>
<game_thermal_config>
    <version>20230829</version>
    <filter-name>game_thermal_config</filter-name>
    <heavy_policy>
        <game_control temp="520" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="60"/>
    </heavy_policy>
    <default_policy>
        <game_control temp="430" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="440" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="450" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="460" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="470" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="480" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="490" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="510" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
    </default_policy>
</game_thermal_config>' > "$module$file"
  else
  echo '<?xml version="1.0" encoding="utf-8"?>
<game_thermal_config>
    <version>20230829</version>
    <filter-name>game_thermal_config</filter-name>
    <heavy_policy>
        <game_control temp="520" cluster0="-1" cluster1="-1" cluster2="-1" fps="60"/>
    </heavy_policy>
    <default_policy>
        <game_control temp="430" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="440" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="450" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="460" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="470" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="480" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="490" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="510" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
    </default_policy>
</game_thermal_config>' > "$module$file"
  fi
done

# QEGA_Config.txt
find $dirs -type f -name "QEGA_Config.txt" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  echo "SkinTemperatureNode:   battery
SkinNodeThrottleTemp:  55000
#GameID   GameAPK    MaxTemperature  MaxCurrent  AvgCurrent
100001    hok         52000          2000        1800
0         adaptive    55000          2000        1800" > "$module$file"
done

# Preserve commas and unrelated fields in OEM JSON.
find $dirs -type f -name "devices_config.json" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  sed -E \
    -e 's/("battery\.temperate\.range"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"[100,500]"/' \
    -e 's/("high\.capacity\.battery\.temperate\.range"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"[100,500]"/' \
    -e '/"high\.capacity\.threshold"[[:space:]]*:[[:space:]]*100([[:space:]]*[,}]|[[:space:]]*$)/!s/("high\.capacity\.threshold"[[:space:]]*:[[:space:]]*)[0-9]+/\185/' \
    "$file" > "$module$file"
done

# charging_thermal_config_default.txt charging_hyper_mode_config.txt
find $dirs -type f -name "charging_*txt" 2>/dev/null | while IFS= read -r file; do
  mkdir -p "$(dirname "$module$file")"
  echo -n '' > "$module$file"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
     *:=*)
       echo "$line" >> "$module$file"
     ;;
     *,*,*)
       temp=$(echo "$line" | awk -F, '{print $1}')
       current=$(echo "$line" | awk -F, '{print $2}')
       t=$(echo "$line" | awk -F, '{print $3}')
       case "$temp" in
         ""|*[!0-9]*) printf '%s\n' "$line" >> "$module$file"; continue ;;
       esac
       temp=$((temp+50)) # + 5°C
       echo "$temp,$current,$t" >> "$module$file"
     ;;
     *)
       echo "$line" >> "$module$file"
     ;;
    esac
  done < "$file"
done

# D1100/1200
soc=$(getprop ro.board.platform)
if [[ "$soc" == 'mt6891' ]] || [[ "$soc" == 'mt6893' ]] || [[ "$soc" == 'mt6889' ]]; then
  mkdir -p "$module/system/vendor/etc"
  mkdir -p "$module/system/vendor/etc/.tp"
  if [[ -d /odm/etc/powerhal ]]; then
    mkdir -p "$module/odm/etc/powerhal"
  fi

  for file in power_app_cfg.xml powercontable.xml powerscntbl.xml
  do
    cp -f "$SRC/assets/d1x00/$file" "$module/system/vendor/etc/$file"
    if [[ -d /odm/etc/powerhal ]]; then
      cp -f "$SRC/assets/d1x00/$file" "$module/odm/etc/powerhal/$file"
    fi
  done
  cp -f "$SRC/assets/d1x00/tp/ht120.mtc" "$module/system/vendor/etc/.tp/.ht120.mtc"
  cp -f "$SRC/assets/d1x00/tp/thermal_policy_08" "$module/system/vendor/etc/.tp/.thermal_policy_08"
  cp -f "$SRC/assets/d1x00/tp/thermal.conf" "$module/system/vendor/etc/.tp/thermal.conf"
  cp -f "$SRC/assets/d1x00/tp/thermal.off.conf" "$module/system/vendor/etc/.tp/thermal.off.conf"
fi

# Mediatek thermal config
mtk_t=/vendor/etc/thermal
if [[ -d $mtk_t ]]; then
  mkdir -p "$module/system$mtk_t"
  for entry in "$mtk_t"/*
  do
    [ -f "$entry" ] || continue
    file=${entry##*/}
    case $file in
      "disable_"*|"fix_ttj_95.conf")
        cp "$mtk_t/$file" "$module/system$mtk_t/"
      ;;
      "fix_ttj_85.conf")
        [ ! -f "$mtk_t/fix_ttj_95.conf" ] || cp "$mtk_t/fix_ttj_95.conf" "$module/system$mtk_t/$file"
      ;;
      *)
        echo $file
        if [[ -f "$mtk_t/disable_skin_control.conf" ]]; then
         cp "$mtk_t/disable_skin_control.conf" "$module/system$mtk_t/$file"
        else
         [ ! -f "$mtk_t/fix_ttj_95.conf" ] || cp "$mtk_t/fix_ttj_95.conf" "$module/system$mtk_t/$file"
        fi
      ;;
    esac
  done
fi


true
