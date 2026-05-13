import re

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Define _finishClockIn helper
    finish_clock_in_code = """
  void _finishClockIn(Attendance attendance, String bannerMessage) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _topBannerMessage = bannerMessage;
        _currentOpenAttendance = attendance;
        _isProcessing = false;
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        if (_topBannerMessage == bannerMessage) {
          setState(() => _topBannerMessage = null);
        }
      });
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _loadOpenAttendance();
          _loadWorkerData();
          _loadDashboardData();
        }
      });
    });
  }

"""

    # Insert _finishClockIn before _finishClockOut
    if '_finishClockIn(' not in content:
        idx = content.find('  void _finishClockOut(String bannerMessage) {')
        content = content[:idx] + finish_clock_in_code + content[idx:]

    # Now, find the part inside _clockIn where it shows the banner and does enqueueBossAttendanceNotification
    
    # In both files, _clockIn ends with:
    #       if (shift != null) {
    #         final late = lateMinutes(
    #           ...
    #         if (status == 'pending_approval' || status == 'Unplanned') {
    #           ...
    #         }
    #     } catch (e) {
    
    start_banner = content.find('      if (shift != null) {\n        final late = lateMinutes')
    if start_banner == -1:
        print(f"Cannot find banner section in {filepath}")
        return
        
    end_banner = content.find('    } catch (e) {', start_banner)
    
    old_banner_section = content[start_banner:end_banner]
    
    # We replace it with logic that accumulates bannerMessage and calls _finishClockIn at the end
    new_banner_section = """      String bannerMessage = '';
      if (shift != null) {
        final late = lateMinutes(
          actualClockIn: now,
          scheduledStart: shift.scheduledStart,
        );
        if (late > 0) {
          bannerMessage = '오늘 $late분 지각하셨습니다';
        } else if (now.isBefore(shift.scheduledStart)) {
          final h = shift.scheduledStart.hour;
          bannerMessage = '일찍 오셨네요! 출근 기록은 완료되었으며, 근무시간은 $h시부터 입니다.';
        } else {
          bannerMessage = '출근 처리되었습니다';
        }
      } else {
        bannerMessage = '근무표에 없는 출근입니다. 사장님 승인을 기다려 주세요.';
      }

      if (status == 'pending_approval' || status == 'Unplanned') {
        final name = worker['name']?.toString() ?? '직원';
        await _dbService.enqueueBossAttendanceNotification(
          storeId: widget.storeId,
          workerId: _workerId,
          workerName: name,
          kind: 'clock_in_pending',
          message: shift == null
              ? '근무표에 없는 날 출근 요청: $name님'
              : '근무표와 다른 시간대 출근 요청: $name님',
        );
      }
      
      _finishClockIn(attendance, bannerMessage);
"""
    
    content = content[:start_banner] + new_banner_section + content[end_banner:]
    
    # Write back
    with open(filepath, 'w') as f:
        f.write(content)
    print(f"Patched {filepath}")

patch_file('apps/boss_mobile/lib/screens/alba/alba_main_screen.dart')
patch_file('apps/alba_web/lib/screens/alba_main_screen.dart')
