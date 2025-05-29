simple_camera_capture_ui.m 

function captured_image = simple_camera_capture_ui()
% SIMPLE_CAMERA_CAPTURE_UI Opens a separate dialog for live camera preview and frame capture.
% Returns the captured image, or an empty array if cancelled/failed.

    captured_image = []; % Default return

    % Initialize camera using the main helper function (assuming +camera package)
    % Ensure camera.capture_frame is accessible
    try
        cam_obj = camera.capture_frame('init');
    catch ME_init_pkg
        % Fallback if +camera package is not setup but capture_frame.m is directly on path
        warning('Could not call camera.capture_frame, trying direct capture_frame call for init.');
        try
            cam_obj = capture_frame('init');
        catch ME_init_direct
             errordlg(sprintf('Failed to initialize camera via camera.capture_frame or capture_frame:\n%s\n%s', ME_init_pkg.message, ME_init_direct.message), 'Camera Init Error');
             return;
        end
    end
    
    if isempty(cam_obj)
        errordlg('Не удалось инициализировать камеру.', 'Ошибка камеры');
        return;
    end

    % Create dialog
    screen_size = get(0, 'ScreenSize');
    
    % Attempt to get camera resolution for dialog sizing
    try
        pause(0.1); % Brief pause for properties to populate
        resStr = char(cam_obj.Resolution); 
        dims = sscanf(resStr, '%dx%d');
        img_width = dims(1); 
        img_height = dims(2);
    catch
        warning('Could not retrieve camera resolution. Using default 640x480 for dialog sizing.');
        img_width = 640;
        img_height = 480;
    end

    dlg_width = img_width + 40;  % Image width + padding
    dlg_height = img_height + 60 + 40; % Image height + button area + padding
    dlg_pos = [(screen_size(3)-dlg_width)/2, (screen_size(4)-dlg_height)/2, dlg_width, dlg_height];

    hDlg = dialog('Name', 'Захват кадра с камеры', ...
                  'Position', dlg_pos, ...
                  'Units', 'pixels', ... % Ensure units are pixels for positioning
                  'WindowStyle', 'modal', ...
                  'CloseRequestFcn', @cancel_button_callback, ...
                  'Visible', 'off'); % Create invisible, then adjust and make visible

    axCamDlg = axes('Parent', hDlg, 'Units', 'pixels', ...
                    'Position', [20, 70, img_width, img_height]); % x, y, w, h
    set(axCamDlg, 'XTick', [], 'YTick', []);
    
    hImageDlg = image(axCamDlg, uint8(zeros(img_height, img_width, 3))); % Placeholder
    axis(axCamDlg, 'image'); % Maintain aspect ratio

    % Adjust dialog and axes to actual image dimensions if possible
    set(hDlg, 'Position', [(screen_size(3)-dlg_width)/2, (screen_size(4)-dlg_height)/2, dlg_width, dlg_height]);
    set(hDlg, 'Visible', 'on'); % Now make it visible

    % Start preview in the dialog's image object
    try
        preview(cam_obj, hImageDlg); % Direct call to webcam object's preview method
    catch ME_preview
        errordlg(sprintf('Ошибка запуска предпросмотра: %s', ME_preview.message), 'Ошибка предпросмотра');
        cleanup_and_close_dialog(cam_obj, hDlg, true); % Pass true to indicate error state
        return;
    end

    uicontrol('Parent', hDlg, 'Style', 'pushbutton', ...
              'String', 'Зафиксировать кадр', ...
              'FontSize', 10, ...
              'Units', 'pixels', ...
              'Position', [dlg_width/2 - 100, 20, 200, 30], ... % Centered button
              'Callback', @fix_frame_button_callback);

    dialog_data.cam_obj = cam_obj;
    dialog_data.captured_image = []; % Initialize
    guidata(hDlg, dialog_data);

    uiwait(hDlg); % Block execution until uiresume or dialog is deleted

    if ishandle(hDlg) % Check if dialog still exists
        final_dialog_data = guidata(hDlg);
        if isfield(final_dialog_data, 'captured_image')
            captured_image = final_dialog_data.captured_image;
        end
        delete(hDlg); 
    end

    % Nested callbacks
    function fix_frame_button_callback(src, ~)
        fig_handle = ancestor(src, 'figure'); % Get dialog figure handle
        dlg_data_local = guidata(fig_handle); 
        
        if isempty(dlg_data_local) || ~isfield(dlg_data_local, 'cam_obj') || ...
           ~isvalid(dlg_data_local.cam_obj)
            disp('Ошибка: объект камеры не найден в диалоге при фиксации.');
            uiresume(fig_handle); % Unblock to allow cleanup
            return;
        end
        
        try
            snapshot_img = snapshot(dlg_data_local.cam_obj);
            dlg_data_local.captured_image = snapshot_img;
            guidata(fig_handle, dlg_data_local);
        catch ME_snap
            errordlg(sprintf('Ошибка захвата кадра: %s', ME_snap.message),'Ошибка');
            dlg_data_local.captured_image = []; % Ensure empty on error
            guidata(fig_handle, dlg_data_local); 
        end
        
        % Camera is released by cleanup_and_close_dialog after uiresume
        uiresume(fig_handle); 
    end

    function cancel_button_callback(src, ~)
        fig_handle = ancestor(src, 'figure'); % Get dialog figure handle
        dlg_data_local = guidata(fig_handle);
        
        % Ensure captured_image is empty if cancelled
        if ~isempty(dlg_data_local)
            dlg_data_local.captured_image = [];
            guidata(fig_handle, dlg_data_local);
        end
        
        % Camera is released by cleanup_and_close_dialog after uiresume
        uiresume(fig_handle);
    end
    
    % Centralized cleanup for the dialog's camera object
    function cleanup_and_close_dialog(camera_object, dialog_handle, in_error_state)
        if nargin < 3, in_error_state = false; end
        if ~isempty(camera_object) && isvalid(camera_object)
            disp('SimpleCameraUI: Releasing camera object...');
            try
                % Use the main helper function to clear (assumes +camera package)
                camera.capture_frame('clear'); 
            catch ME_clear_pkg
                warning('Could not call camera.capture_frame, trying direct capture_frame call for clear.');
                try
                    capture_frame('clear');
                catch ME_clear_direct
                    fprintf(2,'SimpleCameraUI: Failed to clear camera via helper: %s\n%s\n',ME_clear_pkg.message, ME_clear_direct.message);
                end
            end
        end
        if ishandle(dialog_handle)
            if in_error_state % If called due to an error, we might need to force uiresume if uiwait is active
                if strcmp(get(dialog_handle, 'BeingDeleted'), 'off') % Check if not already being deleted
                    uiresume(dialog_handle); % Try to unblock uiwait
                end
            end
           % delete(dialog_handle) will be handled by the main function after uiwait
        end
    end

    % Final cleanup call for the camera object associated with this dialog
    % This runs after uiwait has finished, regardless of how it finished.
    cleanup_and_close_dialog(cam_obj, hDlg, false);

end

recognize_callback.m

function recognize_callback(hObject, ~)
    % hObject can be used if you need to access guidata from the figure,
    % for now, it primarily interacts with the base workspace.
    
    % Get the frame from the base workspace
    try
        frame = evalin('base','capturedFrame');
    catch
        errordlg('Переменная capturedFrame не найдена в base workspace. Сначала зафиксируйте кадр или загрузите изображение.', 'Ошибка: Нет кадра');
        return;
    end
    
    if isempty(frame)
        errordlg('Переменная capturedFrame пуста. Пожалуйста, повторите захват или загрузку.', 'Ошибка: Пустой кадр');
        return;
    end

    % Call the run_model function
    % This assumes model/run_model.m is accessible via MATLAB's path
    % (e.g., if 'model' subdirectory is on the path or if you've used addpath)
    [label, scores] = run_model(frame); 
    
    % Check if run_model returned an error
    if strcmp(label, 'Ошибка') 
        % The error message would have already been displayed by run_model
        return;
    end
    
    % Display the recognition result
    msgbox(sprintf('Результат: %s (Вероятность: %.2f%%)', string(label), max(scores)*100), 'Результат распознавания');
    
    % Assign results to the base workspace with distinct names
    assignin('base','recognitionLabel',label); 
    assignin('base','recognitionScores',scores);
end

multi_point_ir_scan_ui.m

function scan_results = multi_point_ir_scan_ui(captured_image, hMainFig)
    % MULTI_POINT_IR_SCAN_UI - Создает модальное окно для многоточечного ИК-сканирования.
    %
    %   captured_image: Захваченное изображение для отображения и разметки.
    %   hMainFig:       Хендл главного окна (опционально, для позиционирования или блокировки).
    %
    %   scan_results:   Массив ячеек с результатами сканирования или пустой массив.

    scan_results = []; % Инициализация выходного аргумента
    persistent esp_ip_address_cached_dialog; 

    % --- Параметры сканирования ---
    NUM_SCAN_POINTS = 5; 
    scanPointDataDialog = cell(NUM_SCAN_POINTS, 2); % {Point#, IR Value} - кнопки будут в таблице UI
    pointCoordinatesDialog = []; 
    currentScanningPointDialog = 0;
    isAutoScanningDialog = false;

    % --- Создание модального окна ---
    screenSize = get(0, 'ScreenSize');
    dialogWidth = 0.7; % Относительно экрана
    dialogHeight = 0.75;
    dialogX = (screenSize(3) - screenSize(3)*dialogWidth) / 2;
    dialogY = (screenSize(4) - screenSize(4)*dialogHeight) / 2;

    hDialog = figure('Name', 'Многоточечное ИК-сканирование', ...
                     'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
                     'Units', 'pixels', 'Position', [dialogX dialogY screenSize(3)*dialogWidth screenSize(4)*dialogHeight], ...
                     'WindowStyle', 'modal', ... % МОДАЛЬНОЕ ОКНО
                     'CloseRequestFcn', @close_dialog_callback, ...
                     'Visible', 'off', 'Color', [0.92 0.92 0.98]); % Слегка другой цвет фона
    handles_dlg.hDialog = hDialog;
    
    % --- Размещение элементов в модальном окне ---
    % Панель для изображения слева
    handles_dlg.imagePanel = uipanel(hDialog, 'Title', 'Изображение с точками сканирования', ...
                                     'Units', 'normalized', 'Position', [0.02 0.05 0.47 0.93], 'FontSize', 10);
    handles_dlg.axScanImage = axes('Parent', handles_dlg.imagePanel, 'Units', 'normalized', ...
                                   'Position', [0.05 0.05 0.9 0.9]);
    axis(handles_dlg.axScanImage, 'off');

    % Панель для таблицы и управления справа
    handles_dlg.controlPanel = uipanel(hDialog, 'Title', 'Управление и Результаты', ...
                                       'Units', 'normalized', 'Position', [0.51 0.05 0.47 0.93], 'FontSize', 10);

    handles_dlg.hStartAutoScanButton = uicontrol('Parent', handles_dlg.controlPanel, 'Style', 'pushbutton', ...
                                           'String', 'Начать авто-сканирование', 'Units', 'normalized', ...
                                           'Position', [0.1 0.9 0.8 0.07], 'FontSize', 10, ...
                                           'Callback', @start_auto_scan_dialog_callback);

    columnNamesDlg = {'Точка №', 'ИК Напряжение (V)', 'Переснять', 'Изменить'};
    columnEditableDlg = [false, false, false, false];
    columnFormatDlg = {'numeric', 'numeric', 'char', 'char'};
    
    handles_dlg.hScanTable = uitable('Parent', handles_dlg.controlPanel, ...
                                     'Data', cell(NUM_SCAN_POINTS, length(columnNamesDlg)), ...
                                     'ColumnName', columnNamesDlg, 'ColumnEditable', columnEditableDlg, ...
                                     'ColumnFormat', columnFormatDlg, ...
                                     'Units', 'normalized', 'Position', [0.05 0.15 0.9 0.7], ...
                                     'FontSize', 10, 'RowName', [], ...
                                     'CellSelectionCallback', @table_cell_select_dialog_callback);

    handles_dlg.hStatusTextDlg = uicontrol('Parent', handles_dlg.controlPanel, 'Style', 'text', ...
                                       'String', 'Статус: Готов к разметке точек.', 'Units', 'normalized', ...
                                       'Position', [0.1 0.08 0.8 0.05], 'FontSize', 9);
    handles_dlg.hCloseDialogButton = uicontrol('Parent', handles_dlg.controlPanel, 'Style', 'pushbutton', ...
                                           'String', 'Закрыть и сохранить', 'Units', 'normalized', ...
                                           'Position', [0.1 0.01 0.35 0.06], 'FontSize', 10, ...
                                           'Callback', @save_and_close_dialog_callback);
    handles_dlg.hCancelDialogButton = uicontrol('Parent', handles_dlg.controlPanel, 'Style', 'pushbutton', ...
                                           'String', 'Отмена', 'Units', 'normalized', ...
                                           'Position', [0.55 0.01 0.35 0.06], 'FontSize', 10, ...
                                           'Callback', @cancel_dialog_callback);

    guidata(hDialog, handles_dlg); % Сохраняем handles диалога

    % --- Инициализация диалога ---
    imshow(captured_image, 'Parent', handles_dlg.axScanImage);
    axis(handles_dlg.axScanImage, 'image');
    title(handles_dlg.axScanImage, 'Объект для сканирования');
    
    init_scan_table_dialog();
    define_and_draw_points_on_image_dialog(captured_image);
    
    set(hDialog, 'Visible', 'on'); % Делаем окно видимым после отрисовки
    uiwait(hDialog); % Ожидаем закрытия модального окна

    % --- Вложенные функции для модального окна ---
    function init_scan_table_dialog()
        handles_dlg = guidata(hDialog); % Получаем handles диалога
        tableData = cell(NUM_SCAN_POINTS, length(columnNamesDlg));
        for i_dlg = 1:NUM_SCAN_POINTS
            tableData{i_dlg, 1} = i_dlg;
            tableData{i_dlg, 2} = NaN; 
            tableData{i_dlg, 3} = sprintf('<html><button name="rescanDlg" value="%d">Переснять</button></html>', i_dlg);
            tableData{i_dlg, 4} = sprintf('<html><button name="editDlg" value="%d">Изменить</button></html>', i_dlg);
        end
        set(handles_dlg.hScanTable, 'Data', tableData);
        scanPointDataDialog = tableData; % Сохраняем для доступа
        guidata(hDialog, handles_dlg);
    end

    function define_and_draw_points_on_image_dialog(img_dlg)
        handles_dlg = guidata(hDialog);
        axes(handles_dlg.axScanImage);
        hold(handles_dlg.axScanImage, 'on');
        
        if isfield(handles_dlg, 'scan_point_markers_dlg') && all(ishandle(handles_dlg.scan_point_markers_dlg))
            delete(handles_dlg.scan_point_markers_dlg);
        end
        if isfield(handles_dlg, 'scan_point_labels_dlg') && all(ishandle(handles_dlg.scan_point_labels_dlg))
            delete(handles_dlg.scan_point_labels_dlg);
        end

        [imgHeight_dlg, imgWidth_dlg, ~] = size(img_dlg);
        pointCoordinatesDialog = zeros(NUM_SCAN_POINTS, 2);
        handles_dlg.scan_point_markers_dlg = gobjects(NUM_SCAN_POINTS,1);
        handles_dlg.scan_point_labels_dlg = gobjects(NUM_SCAN_POINTS,1);

        paddingX_dlg = imgWidth_dlg / (NUM_SCAN_POINTS + 1) / 2;
        paddingY_dlg = imgHeight_dlg / 6;
        
        if NUM_SCAN_POINTS == 5
            pointCoordinatesDialog(1,:) = [paddingX_dlg + imgWidth_dlg * 0.15, paddingY_dlg + imgHeight_dlg * 0.2];
            pointCoordinatesDialog(2,:) = [paddingX_dlg + imgWidth_dlg * 0.35, paddingY_dlg + imgHeight_dlg * 0.7];
            pointCoordinatesDialog(3,:) = [paddingX_dlg + imgWidth_dlg * 0.55, paddingY_dlg + imgHeight_dlg * 0.4];
            pointCoordinatesDialog(4,:) = [paddingX_dlg + imgWidth_dlg * 0.75, paddingY_dlg + imgHeight_dlg * 0.8];
            pointCoordinatesDialog(5,:) = [paddingX_dlg + imgWidth_dlg * 0.85, paddingY_dlg + imgHeight_dlg * 0.1];
        else
            for i_dlg = 1:NUM_SCAN_POINTS
                 pointCoordinatesDialog(i_dlg,1) = paddingX_dlg + (imgWidth_dlg - 2*paddingX_dlg) * (i_dlg-1)/(NUM_SCAN_POINTS-1+eps);
                 pointCoordinatesDialog(i_dlg,2) = paddingY_dlg + (imgHeight_dlg - 2*paddingY_dlg) * (i_dlg-1)/(NUM_SCAN_POINTS-1+eps);
            end
        end

        for i_dlg = 1:NUM_SCAN_POINTS
            x_dlg = pointCoordinatesDialog(i_dlg,1);
            y_dlg = pointCoordinatesDialog(i_dlg,2);
            handles_dlg.scan_point_markers_dlg(i_dlg) = plot(handles_dlg.axScanImage, x_dlg, y_dlg, 'co', 'MarkerSize', 12, 'MarkerFaceColor', 'c');
            handles_dlg.scan_point_labels_dlg(i_dlg) = text(handles_dlg.axScanImage, x_dlg + 10, y_dlg + 10, num2str(i_dlg), 'Color', 'm', 'FontSize', 14, 'FontWeight', 'bold');
        end
        hold(handles_dlg.axScanImage, 'off');
        set(handles_dlg.hStatusTextDlg, 'String', 'Точки нанесены. Готов к авто-сканированию.');
        guidata(hDialog, handles_dlg);
    end
    
    function highlight_scan_point_dialog(point_idx_dlg, highlight_dlg)
        handles_dlg = guidata(hDialog);
        if ~isfield(handles_dlg, 'scan_point_markers_dlg') || isempty(handles_dlg.scan_point_markers_dlg) || ~ishandle(handles_dlg.scan_point_markers_dlg(1))
            return;
        end
        marker_to_change = handles_dlg.scan_point_markers_dlg(point_idx_dlg);
        if highlight_dlg
            set(marker_to_change, 'MarkerFaceColor', 'g', 'MarkerEdgeColor', 'k', 'MarkerSize', 18);
        else % Сброс или отметка как отсканированной
            % Если точка была успешно отсканирована, можно сделать ее синей
            if ~isnan(scanPointDataDialog{point_idx_dlg, 2})
                 set(marker_to_change, 'MarkerFaceColor', 'b', 'MarkerEdgeColor', 'k', 'MarkerSize', 14);
            else % Если нет данных или ошибка - вернуть к исходному или цвету ошибки
                 set(marker_to_change, 'MarkerFaceColor', 'c', 'MarkerEdgeColor', 'k', 'MarkerSize', 12); % Исходный цвет
            end
        end
        
        % Сброс предыдущей активной точки (если была)
        if highlight_dlg && currentScanningPointDialog > 0 && currentScanningPointDialog ~= point_idx_dlg && currentScanningPointDialog <= NUM_SCAN_POINTS
             prev_marker = handles_dlg.scan_point_markers_dlg(currentScanningPointDialog);
             if ishandle(prev_marker)
                if ~isnan(scanPointDataDialog{currentScanningPointDialog, 2})
                    set(prev_marker, 'MarkerFaceColor', 'b', 'MarkerEdgeColor', 'k', 'MarkerSize', 14);
                else
                    set(prev_marker, 'MarkerFaceColor', 'c', 'MarkerEdgeColor', 'k','MarkerSize', 12);
                end
             end
        end
    end

    function start_auto_scan_dialog_callback(~, ~)
        handles_dlg = guidata(hDialog);
        if isAutoScanningDialog
            isAutoScanningDialog = false;
            set(handles_dlg.hStartAutoScanButton, 'String', 'Начать авто-сканирование');
            set(handles_dlg.hStatusTextDlg, 'String', 'Авто-сканирование остановлено.');
            if currentScanningPointDialog > 0 && currentScanningPointDialog <= NUM_SCAN_POINTS
                highlight_scan_point_dialog(currentScanningPointDialog, false);
            end
            currentScanningPointDialog = 0;
            return;
        end

        if isempty(pointCoordinatesDialog)
            set(handles_dlg.hStatusTextDlg, 'String', 'Ошибка: Точки не определены.');
            return;
        end
        
        tempDataDlg = get(handles_dlg.hScanTable, 'Data');
        for r_dlg = 1:NUM_SCAN_POINTS
            tempDataDlg{r_dlg,2} = NaN;
        end
        set(handles_dlg.hScanTable, 'Data', tempDataDlg);
        scanPointDataDialog = tempDataDlg;

        isAutoScanningDialog = true;
        currentScanningPointDialog = 0;
        set(handles_dlg.hStartAutoScanButton, 'String', 'Остановить сканирование');
        drawnow;

        for i_dlg = 1:NUM_SCAN_POINTS
            if ~isAutoScanningDialog, break; end
            
            currentScanningPointDialog = i_dlg;
            guidata(hDialog, handles_dlg);

            highlight_scan_point_dialog(i_dlg, true);
            set(handles_dlg.hStatusTextDlg, 'String', sprintf('Авто-скан: Поднесите датчик к точке %d...', i_dlg));
            drawnow;
            
            success_dlg = perform_scan_for_point_dialog(i_dlg);
            
            if success_dlg
                set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d отсканирована. IR: %.3f V.', i_dlg, scanPointDataDialog{i_dlg,2}));
                highlight_scan_point_dialog(i_dlg, false); % Отметит синим, если успешно
            else
                if ~isAutoScanningDialog
                    set(handles_dlg.hStatusTextDlg, 'String', sprintf('Сканирование точки %d отменено.', i_dlg));
                else
                    set(handles_dlg.hStatusTextDlg, 'String', sprintf('Ошибка сканирования точки %d или нет данных.', i_dlg));
                end
                highlight_scan_point_dialog(i_dlg, false); % Вернет к исходному или цвету ошибки
            end
            drawnow;
            
            if i_dlg < NUM_SCAN_POINTS && isAutoScanningDialog
                uiwait(msgbox(sprintf('Точка %d обработана. Переместите датчик от объекта. Нажмите ОК для сканирования точки %d.', i_dlg, i_dlg+1), ...
                       'Следующий шаг', 'modal'));
                if ~ishandle(hDialog) || ~isAutoScanningDialog, break; end % Проверка после msgbox
            end
        end
        
        if isAutoScanningDialog
            set(handles_dlg.hStatusTextDlg, 'String', 'Автоматическое сканирование завершено.');
        end
        isAutoScanningDialog = false;
        set(handles_dlg.hStartAutoScanButton, 'String', 'Начать авто-сканирование');
        currentScanningPointDialog = 0;
        guidata(hDialog, handles_dlg);
    end

    function success_dlg = perform_scan_for_point_dialog(point_idx_dlg)
        handles_dlg = guidata(hDialog);
        success_dlg = false;
        
        esp_port_tcp_dlg = 8888;
        if isempty(esp_ip_address_cached_dialog)
            answer_dlg = inputdlg({'Введите IP адрес ESP8266:'}, 'IP ESP (Диалог)', [1 40], {'192.168.0.227'});
            if isempty(answer_dlg), set(handles_dlg.hStatusTextDlg, 'String', 'IP не введен.'); return; end
            esp_ip_address_cached_dialog = strtrim(answer_dlg{1});
        end
        esp_ip_address_dlg = esp_ip_address_cached_dialog;

        tcp_client_dlg_obj = [];
        try
            set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d: Подключение к ESP...', point_idx_dlg)); drawnow;
            tcp_client_dlg_obj = tcpclient(esp_ip_address_dlg, esp_port_tcp_dlg, 'Timeout', 7, 'ConnectTimeout', 7);
            configureTerminator(tcp_client_dlg_obj, "LF");

            set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d: Отправка SCAN...', point_idx_dlg)); drawnow;
            writeline(tcp_client_dlg_obj, "SCAN");

            set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d: Ожидание ответа...', point_idx_dlg)); drawnow;
            tcp_client_dlg_obj.Timeout = 10;
            response_str_dlg = readline(tcp_client_dlg_obj);
            response_str_dlg = strtrim(response_str_dlg);
            
            clear tcp_client_dlg_obj;

            if isempty(response_str_dlg)
                scanPointDataDialog{point_idx_dlg, 2} = NaN;
                set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d: Нет ответа.', point_idx_dlg));
            elseif startsWith(response_str_dlg, "ERROR:", "IgnoreCase", true)
                scanPointDataDialog{point_idx_dlg, 2} = NaN;
                set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d: Ошибка ESP.', point_idx_dlg));
                errordlg(sprintf('ESP сообщил об ошибке для точки %d: %s. Убедитесь, что ESP в режиме "MATLAB Control".', point_idx_dlg, response_str_dlg), 'Ошибка ESP');
            else
                ir_voltage_dlg = str2double(response_str_dlg);
                if isnan(ir_voltage_dlg)
                    scanPointDataDialog{point_idx_dlg, 2} = NaN;
                elseif ir_voltage_dlg < 0
                    scanPointDataDialog{point_idx_dlg, 2} = NaN; 
                else
                    scanPointDataDialog{point_idx_dlg, 2} = ir_voltage_dlg;
                    success_dlg = true;
                end
            end
        catch ME_scan_dlg
            if ~isempty(tcp_client_dlg_obj) && isvalid(tcp_client_dlg_obj), clear tcp_client_dlg_obj; end
            scanPointDataDialog{point_idx_dlg, 2} = NaN;
            set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d: Ошибка связи.', point_idx_dlg));
            errordlg(sprintf('Ошибка связи с ESP для точки %d: %s', point_idx_dlg, ME_scan_dlg.message), 'Ошибка связи');
        end
        
        tempDataDlg = get(handles_dlg.hScanTable, 'Data');
        tempDataDlg{point_idx_dlg, 2} = scanPointDataDialog{point_idx_dlg, 2};
        set(handles_dlg.hScanTable, 'Data', tempDataDlg);
    end

    function table_cell_select_dialog_callback(source_dlg, eventdata_dlg)
        handles_dlg = guidata(hDialog);
        if isempty(eventdata_dlg.Indices) || eventdata_dlg.Indices(2) < 3
            return;
        end
        
        row_dlg = eventdata_dlg.Indices(1);
        col_dlg = eventdata_dlg.Indices(2);
        current_data_dlg = get(source_dlg, 'Data');

        if col_dlg == 3 % "Переснять"
            set(handles_dlg.hStatusTextDlg, 'String', sprintf('Пересъемка точки %d...', row_dlg));
            highlight_scan_point_dialog(row_dlg, true); drawnow;
            success_dlg_rescan = perform_scan_for_point_dialog(row_dlg);
            highlight_scan_point_dialog(row_dlg, false);
             if success_dlg_rescan
                 set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d переснята. IR: %.3f V.', row_dlg, scanPointDataDialog{row_dlg,2}));
            else
                 set(handles_dlg.hStatusTextDlg, 'String', sprintf('Ошибка пересъемки точки %d.', row_dlg));
            end
        elseif col_dlg == 4 % "Изменить"
            prompt_dlg = {sprintf('Новое ИК значение для точки %d:', row_dlg)};
            answer_dlg_edit = inputdlg(prompt_dlg, 'Изменить значение', [1 35], {num2str(current_data_dlg{row_dlg, 2})});
            if ~isempty(answer_dlg_edit)
                newValue_dlg = str2double(answer_dlg_edit{1});
                if ~isnan(newValue_dlg)
                    current_data_dlg{row_dlg, 2} = newValue_dlg;
                    scanPointDataDialog{row_dlg, 2} = newValue_dlg;
                    set(source_dlg, 'Data', current_data_dlg);
                    set(handles_dlg.hStatusTextDlg, 'String', sprintf('Точка %d изменена на %.3f V.', row_dlg, newValue_dlg));
                else
                    errordlg('Некорректный ввод.', 'Ошибка ввода');
                end
            end
        end
        guidata(hDialog, handles_dlg);
    end

    function save_and_close_dialog_callback(~, ~)
        % Собираем результаты из scanPointDataDialog для возврата
        % Только значения ИК, или вся таблица, если нужно
        results_to_return = cell(NUM_SCAN_POINTS, 2); % {Point#, IR Value}
        for i_res = 1:NUM_SCAN_POINTS
            results_to_return{i_res, 1} = scanPointDataDialog{i_res, 1}; % Номер точки
            results_to_return{i_res, 2} = scanPointDataDialog{i_res, 2}; % Значение ИК
        end
        scan_results = results_to_return; % Присваиваем выходному аргументу
        delete(hDialog);
    end
    
    function cancel_dialog_callback(~, ~)
        scan_results = []; % Возвращаем пустой результат при отмене
        delete(hDialog);
    end

    function close_dialog_callback(~, ~) % Вызывается при закрытии окна крестиком
        if uiwaitfid == hDialog % Если окно все еще в режиме uiwait
             scan_results = []; % Возвращаем пустой результат
             uiresume(hDialog); % Явно выходим из uiwait
        end
        % delete(hDialog); % uiwait должен сам позаботиться о закрытии, но можно и здесь
    end

end % Конец функции multi_point_ir_scan_ui

main_app.m

function main_app()
    % Главное окно
    f = figure('Name', 'Система диагностики кожных покровов', ...
        'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
        'Units', 'normalized', 'Position', [0, 0, 1, 1], ...
        'Color', [1 1 1]);

    % Заголовок
    uicontrol('Style', 'text', 'String', 'Оптическая система диагностики кожного покрова', ...
        'FontSize', 24, 'FontWeight', 'bold', ...
        'Units', 'normalized', 'Position', [0.2 0.6 0.6 0.1], ...
        'BackgroundColor', [1 1 1]);

    % Описание
    uicontrol('Style', 'text', 'String', 'Использование ИИ и ИК-сканирования для распознавания поражений кожи', ...
        'FontSize', 16, ...
        'Units', 'normalized', 'Position', [0.25 0.5 0.5 0.05], ...
        'BackgroundColor', [1 1 1]);

    % Кнопка начала
    uicontrol('Style', 'pushbutton', 'String', 'Начать обследование', ...
        'FontSize', 18, 'Callback', @start_examination, ...
        'Units', 'normalized', 'Position', [0.4 0.35 0.2 0.1]);
end

function start_examination(~, ~)
    close(gcf);
    full_ui();
end

full_ui.m

function full_ui()
    % Основное окно работы
    hFig = figure('Name', 'Диагностика', 'NumberTitle', 'off', ...
        'MenuBar', 'none', 'ToolBar', 'none', 'Units', 'normalized', ...
        'Position', [0,0,1,1], 'Color', [0.94 0.94 0.94], ...
        'CloseRequestFcn', @main_close_request_fcn);

    % Панель для выбора источника изображения
    hSourcePanel = uipanel('Parent', hFig, 'Title', 'Источник изображения', ...
                           'FontSize', 10, 'Units', 'normalized', ...
                           'Position', [0.05 0.82 0.45 0.13], 'BackgroundColor', [0.94 0.94 0.94]);

    hUseCamButton = uicontrol('Parent', hSourcePanel, 'Style', 'pushbutton', ...
                              'String', 'Использовать камеру', ...
                              'Units', 'normalized', 'Position', [0.05 0.15 0.43 0.7], ...
                              'FontSize', 10, 'Callback', @acquire_frame_from_camera_dialog_callback);

    hUploadButton = uicontrol('Parent', hSourcePanel, 'Style', 'pushbutton', ...
                              'String', 'Загрузить изображение', ...
                              'Units', 'normalized', 'Position', [0.52 0.15 0.43 0.7], ...
                              'FontSize', 10, 'Callback', @upload_image_from_file);

    % Ось для отображения изображения
    axCam = axes('Parent', hFig, 'Units', 'normalized', ...
                 'Position', [0.05 0.28 0.45 0.52]); % Main image axes
    set(axCam, 'XTick', [], 'YTick', [], 'Box', 'on', 'Color', [1 1 1]);
    title(axCam, 'Область изображения', 'FontSize', 10);

    % Ось для графиков
    axPlot = axes('Parent', hFig, 'Units', 'normalized', ...
                  'Position', [0.60 0.40 0.35 0.50]); % Adjusted: left, bottom, width, height
    title(axPlot, 'Дополнительные данные', 'FontSize', 10);

    % Панель для кнопок управления
    hControlPanel = uipanel('Parent', hFig, 'Title', 'Управление процессом', ...
                            'FontSize', 10, 'Units', 'normalized', ...
                            'Position', [0.05 0.03 0.9 0.23], 'BackgroundColor', [0.94 0.94 0.94]);

    % Row 1 of buttons in Control Panel
    hDrawROIButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                               'String','Нарисовать ROI', ...
                               'Units','normalized','Position',[0.02 0.70 0.22 0.25], ... % Adjusted Y and Height
                               'FontSize', 9, 'Callback',@draw_roi_callback, 'Enable', 'off');
    hConfirmROIButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                                 'String','Подтвердить ROI', ...
                                 'Units','normalized','Position',[0.26 0.70 0.22 0.25], ... % Adjusted Y and Height
                                 'FontSize', 9, 'Callback',@confirm_roi_callback, 'Enable', 'off');
    hUseFullImageButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                                   'String','Исп. всё изображение', ...
                                   'Units','normalized','Position',[0.50 0.70 0.22 0.25], ... % Adjusted Y and Height
                                   'FontSize', 9, 'Callback',@use_full_image_callback, 'Enable', 'off');
    
    % Row 2 of buttons in Control Panel
    % The old "Capture Frame" button is effectively replaced by the camera dialog workflow
    hRecognizeButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                                 'String','Распознать', ...
                                 'Units','normalized','Position',[0.02 0.40 0.22 0.25], ... % Adjusted Y and Height (was 0.26 before)
                                 'FontSize', 10, 'Callback',@recognize_callback_wrapper, 'Enable', 'off');
    hIRScanButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                              'String','ИК-сканирование', ... % Shortened text slightly
                              'Units','normalized','Position',[0.26 0.40 0.22 0.25], ... % Adjusted Y and Height (was 0.50 before)
                              'FontSize', 9, 'Callback',@launch_multi_point_ir_scan_wrapper, 'Enable', 'off');
    
    % Row 3 of buttons in Control Panel
    hDigitalTwinButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                                   'String','Создать цифр. двойник', ...
                                   'Units','normalized','Position',[0.02 0.10 0.22 0.25], ... % Adjusted Y and Height
                                   'FontSize', 9, 'Callback',@build_digital_twin_wrapper, 'Enable', 'off');
    hReportButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                              'String','Сохранить отчет PDF', ...
                              'Units','normalized','Position',[0.26 0.10 0.22 0.25], ... % Adjusted Y and Height
                              'FontSize', 10, 'Callback',@generate_report_wrapper, 'Enable', 'off');

    % Reset Button (spans more height)
    hResetButton = uicontrol('Parent', hControlPanel, 'Style','pushbutton',...
                             'String','Новое обследование', ...
                             'Units','normalized','Position',[0.76 0.10 0.22 0.85], ... % Spans from bottom row up
                             'FontSize', 10, 'Callback',@reset_ui_callback, 'Enable', 'on');

    handles = struct('hFig', hFig, 'axCam', axCam, 'axPlot', axPlot, ...
                     'hUseCamButton', hUseCamButton, 'hUploadButton', hUploadButton, ...
                     'hRecognizeButton', hRecognizeButton, ...
                     'hIRScanButton', hIRScanButton, 'hDigitalTwinButton', hDigitalTwinButton, ...
                     'hReportButton', hReportButton, 'hResetButton', hResetButton, ...
                     'hDrawROIButton', hDrawROIButton, 'hConfirmROIButton', hConfirmROIButton, ...
                     'hUseFullImageButton', hUseFullImageButton, ...
                     'active_webcam_object', [], 'isImageLoaded', false, 'hImageOnAxCam', [], ...
                     'originalUploadedFrame', [], 'currentROI', [], 'captured_image_data', [], ...
                     'hSourcePanel', hSourcePanel, 'hControlPanel', hControlPanel);
    guidata(hFig, handles);
end

function main_close_request_fcn(hObject, ~)
    fprintf('Closing application...\n');
    try camera.capture_frame('clear'); catch ME_clear_cam
        fprintf(2, 'Warning: Could not clear camera on close: %s\n', ME_clear_cam.message);
    end
    evalin('base', 'clear capturedFrame recognitionLabel recognitionScores irData irScanResults digitalTwin camera_object_managed_by_capture_frame');
    try if ishandle(hObject), delete(hObject); end
    catch ME_delete, fprintf(2, 'Error deleting main figure: %s\n', ME_delete.message); end
    disp('Приложение "Диагностика" закрыто.');
end

function reset_ui_callback(hObject, ~)
    handles = guidata(hObject);
    fprintf('Resetting UI...\n');
    try camera.capture_frame('clear'); catch; end 
    handles.active_webcam_object = [];

    cla(handles.axCam); title(handles.axCam, 'Область изображения');
    set(handles.axCam, 'XTick', [], 'YTick', []);
    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam), delete(handles.hImageOnAxCam); handles.hImageOnAxCam = []; end
    if ~isempty(handles.currentROI) && isvalid(handles.currentROI), delete(handles.currentROI); handles.currentROI = []; end
    handles.originalUploadedFrame = [];
    handles.captured_image_data = [];
    
    cla(handles.axPlot); title(handles.axPlot, 'Дополнительные данные');
    evalin('base', 'clear capturedFrame recognitionLabel recognitionScores irData irScanResults digitalTwin');

    set(handles.hUseCamButton, 'Enable', 'on');
    set(handles.hUploadButton, 'Enable', 'on');
    set(handles.hDrawROIButton, 'Enable', 'off');
    set(handles.hConfirmROIButton, 'Enable', 'off');
    set(handles.hUseFullImageButton, 'Enable', 'off');
    set(handles.hRecognizeButton, 'Enable', 'off');
    set(handles.hIRScanButton, 'Enable', 'off');
    set(handles.hDigitalTwinButton, 'Enable', 'off');
    set(handles.hReportButton, 'Enable', 'off');
    
    handles.isImageLoaded = false;
    guidata(handles.hFig, handles);
end

function acquire_frame_from_camera_dialog_callback(hObject, ~)
    handles = guidata(hObject);
    reset_roi_state(handles); 
    
    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam), delete(handles.hImageOnAxCam); handles.hImageOnAxCam = []; end
    cla(handles.axCam); title(handles.axCam, 'Ожидание кадра с камеры...', 'FontSize', 10); drawnow;
    
    try camera.capture_frame('clear'); catch; end
    handles.active_webcam_object = [];

    set(handles.hFig, 'Pointer', 'watch'); drawnow;
    captured_frame_from_dialog = simple_camera_capture_ui(); 
    set(handles.hFig, 'Pointer', 'arrow');

    if ~isempty(captured_frame_from_dialog)
        disp('UI: Frame received from camera dialog.');
        process_acquired_image(handles.hFig, captured_frame_from_dialog, 'Кадр с камеры');
    else
        disp('UI: Camera dialog cancelled or no frame captured.');
        title(handles.axCam, 'Захват с камеры отменен.', 'FontSize', 10);
        set(handles.hUseCamButton, 'Enable', 'on'); 
        set(handles.hUploadButton, 'Enable', 'on'); 
    end
end

function process_acquired_image(hFig, frame_data, source_title_prefix)
    handles = guidata(hFig);

    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam), delete(handles.hImageOnAxCam); handles.hImageOnAxCam = []; end
    cla(handles.axCam); 
    handles.hImageOnAxCam = imshow(frame_data, 'Parent', handles.axCam); 
    axis(handles.axCam, 'image');
    title(handles.axCam, source_title_prefix, 'Interpreter', 'none', 'FontSize', 10);

    handles.originalUploadedFrame = frame_data; 
    handles.captured_image_data = []; 
    assignin('base', 'capturedFrame', []);

    set(handles.hDrawROIButton, 'Enable', 'on');
    set(handles.hUseFullImageButton, 'Enable', 'on');
    set(handles.hConfirmROIButton, 'Enable', 'off'); 
    set(handles.hRecognizeButton, 'Enable', 'off');
    set(handles.hIRScanButton, 'Enable', 'off');

    set(handles.hUseCamButton, 'Enable', 'on'); 
    set(handles.hUploadButton, 'Enable', 'on'); 
        
    handles.isImageLoaded = false; 
    guidata(hFig, handles);
end

function upload_image_from_file(hObject, ~)
    handles = guidata(hObject);
    reset_roi_state(handles);

    try camera.capture_frame('clear'); catch; end
    handles.active_webcam_object = [];

    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam), delete(handles.hImageOnAxCam); handles.hImageOnAxCam = []; end
    cla(handles.axCam);

    [fileName, filePath] = uigetfile({'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', 'Image Files'}, 'Выберите изображение');
    if isequal(fileName,0) || isequal(filePath,0)
        title(handles.axCam, 'Загрузка отменена', 'FontSize', 10); return;
    end
    
    try 
        fullPath = fullfile(filePath, fileName); 
        frame = imread(fullPath);
    catch ME
        errordlg(sprintf('Не удалось загрузить изображение: %s', ME.message), 'Ошибка загрузки'); 
        return; 
    end
    
    process_acquired_image(handles.hFig, frame, ['Загружено: ' fileName]);
end

function draw_roi_callback(hObject, ~)
    handles = guidata(hObject);
    if isempty(handles.originalUploadedFrame)
        errordlg('Сначала получите изображение с камеры или загрузите из файла.', 'Ошибка'); 
        return; 
    end
    if ~isempty(handles.currentROI) && isvalid(handles.currentROI), delete(handles.currentROI); handles.currentROI = []; end
    
    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam)
        set(handles.hImageOnAxCam, 'CData', handles.originalUploadedFrame); 
    else 
        handles.hImageOnAxCam = imshow(handles.originalUploadedFrame, 'Parent', handles.axCam);
        axis(handles.axCam, 'image');
    end
    title(handles.axCam, 'Нарисуйте прямоугольник и подтвердите ROI', 'FontSize', 10);
    
    try
        handles.currentROI = drawrectangle(handles.axCam, 'LineWidth', 2, 'Color', 'r');
        if ~isempty(handles.currentROI) && isvalid(handles.currentROI)
             addlistener(handles.currentROI, 'MovingROI', @(src,evt) roi_moving_callback(src, evt, handles.hFig));
             addlistener(handles.currentROI, 'ROIMoved', @(src,evt) roi_moved_callback(src, evt, handles.hFig));
        end
        set(handles.hConfirmROIButton, 'Enable', 'on');
        set(handles.hDrawROIButton, 'String', 'Перерисовать ROI');
    catch ME
        errordlg(sprintf('Ошибка ROI: %s', ME.message), 'Ошибка ROI');
        if ~isempty(handles.currentROI) && isvalid(handles.currentROI), delete(handles.currentROI); end; handles.currentROI = [];
        set(handles.hConfirmROIButton, 'Enable', 'off');
    end
    guidata(handles.hFig, handles);
end

function roi_moving_callback(~, evt, hFig) 
    handles = guidata(hFig); if isempty(handles) || ~isfield(handles, 'originalUploadedFrame') || isempty(handles.originalUploadedFrame), return; end
    pos = evt.CurrentPosition; imgSize = size(handles.originalUploadedFrame); 
    pos(1) = max(1, pos(1)); pos(2) = max(1, pos(2)); 
    pos(3) = min(imgSize(2) - pos(1), pos(3)); pos(4) = min(imgSize(1) - pos(2), pos(4)); 
    evt.Source.Position = pos; 
end

function roi_moved_callback(src, ~, hFig) 
    handles = guidata(hFig); if isempty(handles) || ~isfield(handles, 'originalUploadedFrame') || isempty(handles.originalUploadedFrame), return; end
    pos = src.Position; imgSize = size(handles.originalUploadedFrame);
    finalPos(1) = max(0.5, pos(1)); finalPos(2) = max(0.5, pos(2)); 
    finalPos(3) = min(imgSize(2) - finalPos(1) + 0.5, pos(3)); finalPos(4) = min(imgSize(1) - finalPos(2) + 0.5, pos(4)); 
    if finalPos(3) < 1, finalPos(3) = 1; end; if finalPos(4) < 1, finalPos(4) = 1; end
    src.Position = finalPos; 
end

function confirm_roi_callback(hObject, ~)
    handles = guidata(hObject);
    if isempty(handles.currentROI) || ~isvalid(handles.currentROI) || isempty(handles.originalUploadedFrame)
        errordlg('ROI не выбран или изображение отсутствует.', 'Ошибка'); return;
    end
    roiPosition = round(handles.currentROI.Position); 
    if roiPosition(3) < 1 || roiPosition(4) < 1, errordlg('Выбранная область слишком мала.', 'Ошибка ROI'); return; end

    try 
        croppedImage = imcrop(handles.originalUploadedFrame, roiPosition);
    catch ME
        errordlg(sprintf('Ошибка обрезки: %s', ME.message), 'Ошибка обрезки'); return; 
    end
    if isempty(croppedImage), errordlg('Результат обрезки пуст.', 'Ошибка обрезки'); return; end

    handles.captured_image_data = croppedImage; 
    assignin('base', 'capturedFrame', croppedImage);
    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam)
        set(handles.hImageOnAxCam, 'CData', croppedImage); 
    else
        handles.hImageOnAxCam = imshow(croppedImage, 'Parent', handles.axCam); 
        axis(handles.axCam, 'image');
    end
    title(handles.axCam, 'Выбранная область (ROI)', 'FontSize', 10);
    delete(handles.currentROI); handles.currentROI = [];

    set(handles.hRecognizeButton, 'Enable', 'on');
    set(handles.hIRScanButton, 'Enable', 'on'); 
    set(handles.hDrawROIButton, 'Enable', 'off'); 
    set(handles.hConfirmROIButton, 'Enable', 'off');
    set(handles.hUseFullImageButton, 'Enable', 'off');
    set(handles.hDrawROIButton, 'String', 'Нарисовать ROI'); 
    handles.isImageLoaded = true; 
    guidata(handles.hFig, handles);
end

function use_full_image_callback(hObject, ~)
    handles = guidata(hObject);
    if isempty(handles.originalUploadedFrame), errordlg('Сначала получите изображение.', 'Ошибка'); return; end
    
    handles.captured_image_data = handles.originalUploadedFrame; 
    assignin('base', 'capturedFrame', handles.originalUploadedFrame);
    if ~isempty(handles.hImageOnAxCam) && isvalid(handles.hImageOnAxCam)
        set(handles.hImageOnAxCam, 'CData', handles.originalUploadedFrame); 
    else
        handles.hImageOnAxCam = imshow(handles.originalUploadedFrame, 'Parent', handles.axCam); 
        axis(handles.axCam, 'image');
    end
    title(handles.axCam, 'Полное изображение', 'FontSize', 10);
    if ~isempty(handles.currentROI) && isvalid(handles.currentROI), delete(handles.currentROI); handles.currentROI = []; end

    set(handles.hRecognizeButton, 'Enable', 'on');
    set(handles.hIRScanButton, 'Enable', 'on');
    set(handles.hDrawROIButton, 'Enable', 'off');
    set(handles.hConfirmROIButton, 'Enable', 'off');
    set(handles.hUseFullImageButton, 'Enable', 'off');
    set(handles.hDrawROIButton, 'String', 'Нарисовать ROI');
    handles.isImageLoaded = true; 
    guidata(handles.hFig, handles);
end

function reset_roi_state(handles)
    if ~isempty(handles.currentROI) && isvalid(handles.currentROI)
        delete(handles.currentROI);
        handles.currentROI = [];
    end
    set(handles.hDrawROIButton, 'Enable', 'off', 'String', 'Нарисовать ROI');
    set(handles.hConfirmROIButton, 'Enable', 'off');
    set(handles.hUseFullImageButton, 'Enable', 'off');
end

function recognize_callback_wrapper(hObject, ~)
    handles = guidata(hObject);
    if ~handles.isImageLoaded || isempty(handles.captured_image_data)
        errordlg('Сначала необходимо получить изображение и выбрать область (или использовать полностью).', 'Ошибка');
        return;
    end
    
    image_to_recognize = handles.captured_image_data;
    set(handles.hFig, 'Pointer', 'watch');
    drawnow;

    try
        disp('Запуск распознавания...');
        
        all_possible_diseases = {'Меланома', 'Базальноклеточный рак', 'Невус (родинка)', 'Себорейный кератоз', 'Дерматит', 'Псориаз', 'Акне', 'Экзема'};
        num_diseases_to_simulate = length(all_possible_diseases);
        simulated_raw_scores = rand(1, num_diseases_to_simulate);
        simulated_probabilities = simulated_raw_scores / sum(simulated_raw_scores); 
        
        [~, high_idx] = max(simulated_probabilities);
        simulated_probabilities(high_idx) = simulated_probabilities(high_idx) + 0.3; 
        simulated_probabilities = simulated_probabilities / sum(simulated_probabilities);

        recognition_results = table(all_possible_diseases(:), simulated_probabilities(:), ...
                                    'VariableNames', {'Disease', 'Probability'});
        
        recognition_results = sortrows(recognition_results, 'Probability', 'descend');
        
        if isempty(recognition_results)
            errordlg('Распознавание не вернуло результатов.', 'Ошибка распознавания');
            set(handles.hFig, 'Pointer', 'arrow');
            return;
        end

        top_recognition_label = recognition_results.Disease{1};
        top_recognition_score = recognition_results.Probability(1);

        assignin('base', 'recognitionLabel', top_recognition_label);
        assignin('base', 'recognitionScores', recognition_results); 

        current_title_obj = get(handles.axCam, 'Title');
        current_title_str = get(current_title_obj, 'String');
        title_text_suffix = sprintf('. Распознано: %s (Вер.: %.2f%%)', top_recognition_label, top_recognition_score*100);
        
        base_title_str = '';
        if ischar(current_title_str)
            if contains(current_title_str, "Полное изображение")
                base_title_str = 'Полное изображение';
            elseif contains(current_title_str, "Выбранная область (ROI)")
                base_title_str = 'Выбранная область (ROI)';
            elseif contains(current_title_str, "Кадр с камеры")
                base_title_str = 'Кадр с камеры';
            else 
                base_title_str = current_title_str; 
                base_title_str = regexprep(base_title_str, '\. Распознано:.*', '');
            end
        end
        if isempty(base_title_str), base_title_str = 'Изображение'; end
        title(handles.axCam, [base_title_str, title_text_suffix]);

        disp(['Наиболее вероятный диагноз: ' top_recognition_label]);

        cla(handles.axPlot); 
        
        num_to_plot = min(5, height(recognition_results)); 
        
        if num_to_plot > 0
            top_diseases_for_plot = recognition_results.Disease(1:num_to_plot);
            top_probabilities_for_plot = recognition_results.Probability(1:num_to_plot);

            bar(handles.axPlot, top_probabilities_for_plot * 100); 
            
            set(handles.axPlot, 'XTick', 1:num_to_plot);
            set(handles.axPlot, 'XTickLabel', top_diseases_for_plot);
            xtickangle(handles.axPlot, 45); 

            ylabel(handles.axPlot, 'Вероятность (%)');
            xlabel(handles.axPlot, 'Диагноз');
            title(handles.axPlot, 'Топ вероятностей диагнозов');
            grid(handles.axPlot, 'on');
            ylim(handles.axPlot, [0 max([top_probabilities_for_plot*100; 10])+5]); 
        else
            title(handles.axPlot, 'Нет данных для отображения вероятностей');
        end
        
        if evalin('base', "exist('irScanResults', 'var') && ~isempty(evalin('base','irScanResults'))")
             set(handles.hDigitalTwinButton, 'Enable', 'on');
        end
        if evalin('base', "exist('irScanResults', 'var') && exist('digitalTwin', 'var')") || ...
           (evalin('base', "exist('irScanResults', 'var') && ~isempty(evalin('base','irScanResults'))") && ~isempty(top_recognition_label))
            set(handles.hReportButton, 'Enable', 'on');
        end
        
    catch ME_rec
        cla(handles.axPlot); 
        title(handles.axPlot, 'Ошибка при распознавании');
        errordlg(['Ошибка распознавания: ' ME_rec.message], 'Ошибка распознавания');
        fprintf(2, 'Ошибка распознавания: %s\nStack:\n', ME_rec.message);
        for k=1:length(ME_rec.stack)
            fprintf(2, 'File: %s, Name: %s, Line: %d\n', ME_rec.stack(k).file, ME_rec.stack(k).name, ME_rec.stack(k).line);
        end
    end
    
    set(handles.hFig, 'Pointer', 'arrow');
    drawnow; 
    guidata(hObject, handles);
end

function launch_multi_point_ir_scan_wrapper(hObject, ~) 
    handles = guidata(hObject);
    if ~handles.isImageLoaded || isempty(handles.captured_image_data)
        errordlg('Сначала необходимо получить изображение и выбрать область (или использовать полностью).', 'Ошибка');
        return;
    end
    current_frame_for_scan = handles.captured_image_data;
    
    set(handles.hFig, 'Pointer', 'watch'); disp('Запуск multi_point_ir_scan_ui...');
    ir_scan_results = multi_point_ir_scan_ui(current_frame_for_scan, handles.hFig); 
    set(handles.hFig, 'Pointer', 'arrow');
    if ~isempty(ir_scan_results)
        assignin('base', 'irScanResults', ir_scan_results); assignin('base', 'irData', ir_scan_results); 
        disp('Результаты ИК-сканирования:'); disp(ir_scan_results);
        if evalin('base', "exist('recognitionLabel', 'var') && ~isempty(evalin('base','recognitionLabel'))")
             set(handles.hDigitalTwinButton, 'Enable', 'on');
        end
        if evalin('base', "exist('recognitionLabel', 'var') && exist('digitalTwin', 'var')") 
            set(handles.hReportButton, 'Enable', 'on');
        end
    else, disp('Многоточечное ИК-сканирование отменено/нет результатов.'); end
    guidata(hObject, handles);
end

function build_digital_twin_wrapper(hObject, ~) 
    handles = guidata(hObject);
    if ~(handles.isImageLoaded && ~isempty(handles.captured_image_data) && ...
         evalin('base', "exist('recognitionLabel', 'var') && ~isempty(evalin('base','recognitionLabel'))") && ...
         evalin('base', "exist('irScanResults', 'var') && ~isempty(evalin('base','irScanResults'))"))
        errordlg('Нужны: обработанный кадр, распознавание, ИК-результаты.', 'Ошибка данных ЦД'); return;
    end
    
    disp('Запуск build_digital_twin...');
    pause(1); digital_twin_data.info = "Цифровой двойник создан"; assignin('base', 'digitalTwin', digital_twin_data);
    disp('Цифровой двойник создан (имитация).');
    if evalin('base', "exist('recognitionScores', 'var')"), set(handles.hReportButton, 'Enable', 'on'); end
    guidata(hObject, handles);
end

function generate_report_wrapper(hObject, ~) 
    handles = guidata(hObject);
    if isempty(handles.captured_image_data)
         errordlg('Для отчета отсутствует обработанный кадр в UI.', 'Ошибка данных для отчета'); return;
    end
    assignin('base', 'capturedFrame', handles.captured_image_data);

    required_vars = {'capturedFrame', 'recognitionLabel', 'recognitionScores', 'irScanResults', 'digitalTwin'};
    missing_vars = {}; allExistAndNotEmpty = true;
    for i = 1:length(required_vars)
        var_name = required_vars{i};
        if evalin('base', sprintf("exist('%s', 'var')", var_name))
            varValue = evalin('base', var_name);
            is_empty_check = isempty(varValue);
            if iscell(varValue) && (isequal(size(varValue),[0 2]) || (size(varValue,1)==0 && size(varValue,2)==2) )
                 is_empty_check = true; 
            end
            if is_empty_check && ~(isnumeric(varValue) && isequal(size(varValue),[0 0])) 
                allExistAndNotEmpty = false; missing_vars{end+1} = var_name; %#ok<AGROW>
            end
        else, allExistAndNotEmpty = false; missing_vars{end+1} = var_name; %#ok<AGROW>
        end
    end
    if ~allExistAndNotEmpty, errordlg(sprintf('Для отчета отсутствуют/пусты данные: %s.', strjoin(unique(missing_vars), ', ')), 'Ошибка данных для отчета'); return; end
    
    disp('Запуск generate_report...');
    pause(1); 
    [file, path] = uiputfile('Отчет_Диагностики.pdf', 'Сохранить отчет как PDF');
    if isequal(file,0) || isequal(path,0)
        disp('Сохранение отчета отменено.');
    else
        save(fullfile(path, [file(1:end-3) 'mat']), required_vars{:}); 
        msgbox(sprintf('Отчет сохранен (имитация как .mat) в:\n%s', fullfile(path, file)), 'Генерация отчета');
        disp('Отчет сгенерирован (имитация).');
    end
    guidata(hObject,handles);
end

utils/report_generator.m

function generate_report(~,~) % src argument is not used, can be ~
    % Retrieve data from base workspace
    try
        frame = evalin('base','capturedFrame');
        label = evalin('base','recognitionLabel'); % Changed from 'label'
        scores = evalin('base','recognitionScores'); % Changed from 'scores'
        irData = evalin('base','irData');
        twin = evalin('base','digitalTwin');
    catch ME
        errordlg(sprintf('Не удалось получить все необходимые данные из base workspace для отчета: %s\nУбедитесь, что все этапы (захват, распознавание, ИК, двойник) выполнены.', ME.message), 'Ошибка данных для отчета');
        return;
    end

    % Check if all necessary variables were actually retrieved and are not empty
    missingVars = {};
    if ~exist('frame','var') || isempty(frame), missingVars{end+1} = 'capturedFrame'; end
    if ~exist('label','var') || isempty(label), missingVars{end+1} = 'recognitionLabel'; end
    if ~exist('scores','var') || isempty(scores), missingVars{end+1} = 'recognitionScores'; end
    if ~exist('irData','var') || isempty(irData), missingVars{end+1} = 'irData'; end
    if ~exist('twin','var') || isempty(twin), missingVars{end+1} = 'digitalTwin'; end

    if ~isempty(missingVars)
        errordlg(sprintf('Для генерации отчета отсутствуют или пусты следующие данные: %s.', strjoin(missingVars, ', ')), 'Ошибка данных для отчета');
        return;
    end

    import mlreportgen.report.*;
    import mlreportgen.dom.*;

    try
        % Ensure the 'report' directory exists
        if ~isfolder('report')
            mkdir('report');
        end
        rpt = Report('report/diagnosis_report','pdf');
        
        % Title Page
        tp = TitlePage('Title','Отчет обследования кожных покровов');
        try
            currentUser = getenv('USERNAME'); % Windows
            if isempty(currentUser), currentUser = getenv('USER'); end % Linux/macOS
            if ~isempty(currentUser), tp.Author = currentUser; end
        catch
            % Silently ignore if username cannot be fetched
        end
        tp.PubDate = datestr(now, 'dd-mmm-yyyy HH:MM:SS');
        add(rpt, tp);
        
        % Classification Results Section
        secClassification = Section('Результаты классификации');
        paraTextStr = sprintf('Диагноз: %s', string(label));
        if isnumeric(scores) && ~isempty(scores) && numel(scores) > 0
             paraTextStr = [paraTextStr, sprintf(' (Вероятность наиболее вероятного класса: %.2f%%)', max(scores)*100)];
        end
        add(secClassification, Paragraph(paraTextStr));
        
        imgCapturedTitle = Paragraph('Захваченное изображение:');
        imgCapturedTitle.FontSize = '12pt';
        imgCapturedTitle.Bold = true;
        add(secClassification, imgCapturedTitle);
        
        figCaptured = Figure(Image(frame));
        figCaptured.SnapshotFormat = 'png';
        figCaptured.Caption = 'Оригинальное изображение для анализа';
        add(secClassification, figCaptured);
        add(rpt, secClassification);
        
        % Digital Twin Section
        secDigitalTwin = Section('Цифровой двойник и ИК-данные');
        
        imgTwinTitle = Paragraph('Визуализация цифрового двойника:');
        imgTwinTitle.FontSize = '12pt';
        imgTwinTitle.Bold = true;
        add(secDigitalTwin, imgTwinTitle);

        figTwin = Figure(Image(twin));
        figTwin.SnapshotFormat = 'png';
        figTwin.Caption = 'Цифровой двойник (комбинация видимого спектра и ИК-данных)';
        add(secDigitalTwin, figTwin);

        if isnumeric(irData) && ~isempty(irData)
            irPlotTitle = Paragraph('Данные ИК-сканирования:');
            irPlotTitle.FontSize = '12pt';
            irPlotTitle.Bold = true;
            add(secDigitalTwin, irPlotTitle);
            
            tempFig = figure('Visible', 'off', 'Units', 'pixels', 'Position', [0 0 600 400]);
            plot(irData);
            title('График ИК-сканирования');
            xlabel('Индекс данных');
            ylabel('Значение ИК-сигнала');
            grid on;
            
            imgIR = Image(getframe(tempFig).cdata);
            figIR = Figure(imgIR);
            figIR.SnapshotFormat = 'png';
            figIR.Caption = 'Графическое представление данных ИК-сканирования';
            add(secDigitalTwin, figIR);
            close(tempFig);
        end
        add(rpt, secDigitalTwin);
        
        close(rpt);
        rptview(rpt);
        msgbox('Отчет успешно создан и открыт.', 'Генерация отчета', 'help');

    catch ME_report
        errMsg = sprintf('Ошибка при генерации PDF отчета: %s', ME_report.message);
        if ~isempty(ME_report.stack)
            errMsg = sprintf('%s\nВ файле: %s (строка %d)', errMsg, ME_report.stack(1).name, ME_report.stack(1).line);
        end
        errordlg(errMsg, 'Ошибка генерации отчета');
    end
end

utils/imblend.m

function out = imblend(im1, im2, alpha)
    out = uint8(alpha*double(im2) + (1-alpha)*double(im1));
end


utils/build_digital_twin.m

function build_digital_twin(src,~)
    frame = evalin('base','capturedFrame');
    irData = evalin('base','irData');
    % Формируем тепловую карту
    im = imresize(frame, [size(irData,1), size(irData,2)]);
    hmap = ind2rgb(uint8(mat2gray(irData)*255), parula(256));
    twin = imblend(im, hmap, 0.5);
    figure; imshow(twin); title('Цифровой двойник');
    assignin('base','digitalTwin',twin);
end

model/run_model.m

function [label, scores] = run_model(frame)
    persistent classifier
    if isempty(classifier)
        % Path to the model file.
        % Assumes 'model' is a subdirectory of the current path, or an absolute path.
        modelFilePath = 'model/skinDiseaseClassifier_03.mat'; 
        
        % Attempt to load from 'skinDiseaseClassifier_03.mat' in the current directory
        % if 'model/skinDiseaseClassifier_03.mat' is not found. This helps if run_model.m
        % is itself inside the 'model' directory.
        if exist(modelFilePath, 'file') ~= 2 && exist('skinDiseaseClassifier_03.mat', 'file') == 2
            modelFilePath = 'skinDiseaseClassifier_03.mat';
        end

        try
            data = load(modelFilePath);
        catch ME
            errordlg(sprintf('Не удалось загрузить файл модели: %s\nУбедитесь, что файл существует и находится в правильной директории.\nОшибка MATLAB: %s', modelFilePath, ME.message), 'Ошибка загрузки модели');
            label = 'Ошибка'; scores = 0;
            return;
        end
        
        expectedVarName = 'trainedNet'; % ИЗМЕНЕНО: The variable name expected inside the .mat file
        
        if isfield(data, expectedVarName)
            classifier = data.(expectedVarName);
        else
            availableVars = fields(data);
            if isempty(availableVars)
                errMsg = sprintf('Файл модели "%s" загружен, но он пуст (не содержит переменных).', modelFilePath);
            else
                errMsg = sprintf('Ожидаемая переменная "%s" не найдена в файле модели "%s".\nНайденные переменные: %s.\n\nПожалуйста, проверьте имя переменной в файле .mat или обновите "expectedVarName" в коде run_model.m.', ...
                                 expectedVarName, modelFilePath, strjoin(availableVars, ', '));
            end
            errordlg(errMsg, 'Ошибка переменной в модели');
            label = 'Ошибка'; scores = 0;
            classifier = []; % Ensure classifier remains empty to prevent repeated errors without fix
            return;
        end
    end
    
    % If classifier failed to load in a previous step
    if isempty(classifier)
        % An error message should have already been displayed
        label = 'Ошибка'; scores = 0;
        return;
    end

    % Preprocess the image
    try
        im = imresize(frame, [224 224]); % Убедитесь, что этот размер соответствует imageSize из вашего .mat файла, если imageSize используется для чего-то еще
        im = im2single(im);
    catch ME_preprocess
        errordlg(sprintf('Ошибка при предобработке изображения: %s', ME_preprocess.message),'Ошибка предобработки');
        label = 'Ошибка'; scores = 0;
        return;
    end

    % Classify the image
    try
        [label, scores] = classify(classifier, im);
    catch ME_classify
        errordlg(sprintf('Ошибка при классификации изображения: %s\nУбедитесь, что модель совместима с функцией classify и входными данными.', ME_classify.message),'Ошибка классификации');
        label = 'Ошибка'; scores = 0;
        return;
    end
end

model/skinDiseaseClassifier_03.mat

ir_sensor/ir_scan_callback.m

function ir_scan_callback(hObject,~)
    handles = guidata(hObject);
    if ~isfield(handles, 'axPlot')
        errordlg('Не удалось найти ось для графика ИК-данных (axPlot) в handles.', 'Ошибка GUI');
        return;
    end
    if ~isfield(handles, 'hFig')
        current_fig = gcbf; 
        if isempty(current_fig) && ishandle(hObject)
            current_fig = ancestor(hObject, 'figure');
        end
        if isempty(current_fig)
            errordlg('Не удалось найти главный figure handle (hFig).', 'Ошибка GUI');
            return;
        else
            handles.hFig = current_fig; 
        end
    end

    persistent esp_ip_address_cached;

    % --- НАСТРОЙКИ ESP8266 ---
    esp_port_tcp = 8888; % TCP порт, указанный в скетче ESP для MATLAB
    % -------------------------

    if isempty(esp_ip_address_cached) || strcmp(esp_ip_address_cached, 'YOUR_ESP_IP_ADDRESS')
        prompt = {'Введите IP адрес ESP8266:'};
        dlgtitle = 'IP адрес ИК-сканера';
        dims = [1 40];
        definput = {'192.168.0.227'}; % Замените на IP вашего ESP
        answer = inputdlg(prompt,dlgtitle,dims,definput);
        if isempty(answer) || isempty(answer{1})
            disp('IP адрес не введен. Операция ИК-сканирования отменена.');
            title(handles.axPlot, 'ИК-сканирование отменено (нет IP)');
            return;
        end
        esp_ip_address_cached = strtrim(answer{1});
    end
    
    esp_ip_address = esp_ip_address_cached;

    cla(handles.axPlot);
    title(handles.axPlot, 'Подключение к ИК-сканеру (MATLAB)...', 'FontSize', 10);
    drawnow;

    tcp_client = []; 

    try
        fprintf('Попытка подключения к ESP (MATLAB TCP): %s:%d\n', esp_ip_address, esp_port_tcp);
        tcp_client = tcpclient(esp_ip_address, esp_port_tcp, 'Timeout', 7, 'ConnectTimeout', 7); % Таймауты можно подстроить
        configureTerminator(tcp_client, "LF");

        title(handles.axPlot, 'Отправка команды SCAN...', 'FontSize', 10);
        drawnow;

        writeline(tcp_client, "SCAN");
        disp('Команда SCAN отправлена на ESP.');

        title(handles.axPlot, 'Ожидание ответа от сканера...', 'FontSize', 10);
        drawnow;
        
        tcp_client.Timeout = 10; 
        response_str = readline(tcp_client);
        response_str = strtrim(response_str); 
        fprintf('Получен ответ от ESP: "%s"\n', response_str);

        clear tcp_client; 
        disp('TCP соединение с ESP закрыто.');

        if isempty(response_str)
            errordlg('Сканер не вернул данные (пустой ответ). Убедитесь, что ESP в режиме MATLAB Control.', 'Ошибка ИК-сканера');
            title(handles.axPlot, 'Ошибка: Пустой ответ', 'FontSize', 10);
            return;
        end

        if startsWith(response_str, "ERROR:", "IgnoreCase", true)
            errordlg(sprintf('ESP сообщил об ошибке: %s. Убедитесь, что ESP в режиме "MATLAB Control" через веб-страницу.', response_str), 'Ошибка ESP');
            title(handles.axPlot, 'Ошибка от ESP', 'FontSize', 10);
            return;
        end
        
        ir_voltage = str2double(response_str);
            
        if isnan(ir_voltage)
            errordlg(sprintf('Не удалось распознать данные от сканера. Получено: "%s"', response_str), 'Ошибка парсинга ИК');
            title(handles.axPlot, 'Ошибка парсинга ответа', 'FontSize', 10);
            return;
        end

        if ir_voltage < 0 
            fprintf('[INFO] IR Scan (MATLAB): No valid measurement (Distance > 30mm or VL53L0X error).\n');
            cla(handles.axPlot);
            text(handles.axPlot, 0.5, 0.5, 'Нет ИК-измерения для MATLAB (объект >30мм или ошибка)', ...
                 'HorizontalAlignment', 'center', 'FontSize', 10, 'Color', 'red');
            set(handles.axPlot, 'XTick', [], 'YTick', []);
            title(handles.axPlot, 'Результат ИК-сканирования', 'FontSize', 10);
            if evalin('base', "exist('irData', 'var')"), evalin('base', "clear irData"); end
        else
            fprintf('[INFO] IR Scan Result (MATLAB): Voltage = %.3f V\n', ir_voltage);
            cla(handles.axPlot);
            text(handles.axPlot, 0.5, 0.5, sprintf('ИК напряжение: %.3f V', ir_voltage), ...
                 'HorizontalAlignment', 'center', 'FontSize', 14, 'FontWeight', 'bold');
            set(handles.axPlot, 'XTick', [], 'YTick', []);
            title(handles.axPlot, 'Результат ИК-сканирования', 'FontSize', 10);

            irSensorReading.voltage = ir_voltage;
            assignin('base','irData', irSensorReading);
            disp(['Сохранено irData.voltage = ' num2str(ir_voltage)]);
            
            if evalin('base', "exist('capturedFrame', 'var') && exist('recognitionLabel', 'var')")
                 if isfield(handles, 'hDigitalTwinButton') && isgraphics(handles.hDigitalTwinButton)
                    set(handles.hDigitalTwinButton, 'Enable', 'on');
                 end
            end
        end
        drawnow;

    catch ME
        errordlg(sprintf('Ошибка при связи с ИК-сканером (%s:%d):\n%s. Убедитесь, что ESP включен и в правильном режиме.', esp_ip_address, esp_port_tcp, ME.message), 'Ошибка связи ИК');
        title(handles.axPlot, 'Ошибка связи с ИК-сканером', 'FontSize', 10);
        if ~isempty(tcp_client) && isvalid(tcp_client), clear tcp_client; end 
        disp('TCP соединение с ESP закрыто из-за ошибки.');
        return;
    end
end

ir_sensor/ir_module.m

function ir_data = ir_scan_callback(src,~)
    data = guidata(src);
    % Запрос данных из NodeMCU по HTTP
    url = 'http://192.168.4.1/ir';
    ir_data = webread(url);
    % Отобразить график
    axes(data.axPlot); plot(ir_data);
    title('ИК-сканирование');
    assignin('base','irData',ir_data);
end

+camera/capture_frame.m

function varargout = capture_frame(action, varargin)
% CAPTURE_FRAME Manages webcam operations: init, preview, snapshot, clear.
% (Using MATLAB's modern 'webcam' objects)

persistent hFigPreview_internal % Persistent handle for internal preview window

varargout = {}; % Default empty output
base_cam_var_name = 'camera_object_managed_by_capture_frame'; % Consistent name

switch lower(action)
    case 'init'
        current_cam_obj = [];
        if evalin('base', sprintf("exist('%s', 'var')", base_cam_var_name))
            current_cam_obj = evalin('base', base_cam_var_name);
            if ~isvalid(current_cam_obj) || ~isa(current_cam_obj, 'webcam')
                fprintf('[capture_frame] Existing %s is invalid or not a webcam. Re-initializing.\n', base_cam_var_name);
                current_cam_obj = [];
            else
                disp('[capture_frame] Using existing valid webcam object from base workspace.');
            end
        end

        if isempty(current_cam_obj)
            try
                camList = webcamlist;
                if isempty(camList)
                    error('No webcams detected. Check connections/drivers and MATLAB Support Package for USB Webcams.');
                end
                fprintf('[capture_frame] Initializing webcam: %s\n', camList{1});
                current_cam_obj = webcam(1); % Use the first webcam
                assignin('base', base_cam_var_name, current_cam_obj);
                disp(['[capture_frame] New webcam object created and stored as ', base_cam_var_name]);
            catch ME
                errordlg(sprintf('[capture_frame] Error initializing webcam: %s', ME.message), 'Webcam Init Error');
                current_cam_obj = [];
            end
        end
        varargout{1} = current_cam_obj;

    case 'start_preview' % For GUI image handle
        if nargin < 2 % action, imgHandle, [cam_obj_optional]
            error('[capture_frame] Not enough arguments for start_preview. Need image handle.');
        end
        imgHandle = varargin{1}; % Image handle IS used
        
        cam_obj = [];
        if nargin > 2 && ~isempty(varargin{2}) && isa(varargin{2}, 'webcam') && isvalid(varargin{2})
            cam_obj = varargin{2};
        elseif evalin('base', sprintf("exist('%s', 'var')", base_cam_var_name))
            base_obj = evalin('base', base_cam_var_name);
            if isa(base_obj, 'webcam') && isvalid(base_obj)
                cam_obj = base_obj;
            end
        end

        if ~isempty(cam_obj)
            try
                preview(cam_obj, imgHandle); % This starts the live update to imgHandle
                disp('[capture_frame] Preview started on provided image handle.');
            catch ME
                errordlg(sprintf('[capture_frame] Error starting preview: %s', ME.message), 'Preview Error');
            end
        else
            warning('[capture_frame] No valid camera object found to start preview.');
        end

    case 'stop_preview' % Mainly for internal preview window cleanup
        disp('[capture_frame] ''stop_preview'' action called (primarily for internal preview cleanup).');
        if ~isempty(hFigPreview_internal) && ishandle(hFigPreview_internal)
            try 
                disp('[capture_frame] Closing internal snapshot preview window.');
                delete(hFigPreview_internal); 
            catch ME_closing_internal
                fprintf(2, '[capture_frame] Error closing internal preview: %s\n', ME_closing_internal.message);
            end
            hFigPreview_internal = [];
        else
            %disp('[capture_frame] No internal snapshot preview window to close.');
        end
        % Actual stopping of preview on a GUI handle is done by deleting the webcam object
        % or by the GUI no longer allowing updates / replacing the image content.

    case 'snapshot'
        show_internal_preview = false;
        if nargin > 1 && islogical(varargin{1})
            show_internal_preview = varargin{1};
        end
        
        cam_obj = [];
        idx = 1; if islogical(varargin{1}), idx=2; end % Adjust index if show_internal_preview was passed

        if nargin > idx && ~isempty(varargin{idx}) && isa(varargin{idx},'webcam') && isvalid(varargin{idx})
            cam_obj = varargin{idx};
        elseif evalin('base', sprintf("exist('%s', 'var')", base_cam_var_name))
            base_obj = evalin('base', base_cam_var_name);
            if isa(base_obj, 'webcam') && isvalid(base_obj)
                cam_obj = base_obj;
            end
        end
        
        if isempty(cam_obj)
            disp('[capture_frame] Camera not initialized for snapshot. Initializing now.');
            cam_obj = camera.capture_frame('init'); % Ensure package notation if used
            if isempty(cam_obj), varargout{1} = []; return; end
        end
        
        img = [];
        if ~isempty(cam_obj) && isvalid(cam_obj)
            if show_internal_preview
                if ~isempty(hFigPreview_internal) && ishandle(hFigPreview_internal)
                    try delete(hFigPreview_internal); catch; end
                end
                hFigPreview_internal = figure('Name', 'Camera Preview - Close to Capture', ...
                                            'NumberTitle', 'off', 'CloseRequestFcn', 'uiresume(gcbf)');
                try
                    img_for_prev = snapshot(cam_obj);
                    imshow(img_for_prev, 'Parent',gca);
                    title('Close this window to capture frame');
                    uiwait(hFigPreview_internal);
                catch ME_internal_prev
                    errordlg(sprintf('[capture_frame] Error during internal preview: %s', ME_internal_prev.message),'Internal Preview Error');
                    if ishandle(hFigPreview_internal), delete(hFigPreview_internal); end
                    hFigPreview_internal = []; varargout{1} = []; return;
                end
                if ishandle(hFigPreview_internal), delete(hFigPreview_internal); end
                hFigPreview_internal = []; 
            end
            
            try
                img = snapshot(cam_obj);
                disp('[capture_frame] Snapshot taken.');
            catch ME
                errordlg(sprintf('[capture_frame] Error taking snapshot: %s', ME.message), 'Snapshot Error');
                img = [];
            end
        else
            warning('[capture_frame] No valid camera object for snapshot.'); img = [];
        end
        varargout{1} = img;

    case 'clear'
        disp('[capture_frame] ''clear'' action called.');
        cam_obj_to_clear = [];
        if evalin('base', sprintf("exist('%s', 'var')", base_cam_var_name))
            cam_obj_to_clear = evalin('base', base_cam_var_name);
            if isa(cam_obj_to_clear, 'webcam') && isvalid(cam_obj_to_clear)
                disp(['[capture_frame] Deleting webcam object: ', get(cam_obj_to_clear, 'Name')]);
                delete(cam_obj_to_clear); % This stops any preview it was managing
            else
                disp('[capture_frame] Object in base was not a valid webcam or already invalid.');
            end
            evalin('base', sprintf("clear %s", base_cam_var_name));
            disp(['[capture_frame] Cleared ', base_cam_var_name, ' from base workspace.']);
        else
            disp('[capture_frame] No base workspace variable to clear.');
        end

        if ~isempty(hFigPreview_internal) && ishandle(hFigPreview_internal)
            try delete(hFigPreview_internal); catch; end
            hFigPreview_internal = [];
        end
    otherwise
        error('[capture_frame] Unknown action: %s.', action);
end
end